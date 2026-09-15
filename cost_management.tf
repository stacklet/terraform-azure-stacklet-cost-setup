data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "current" {
  name     = substr("Stacklet-${var.customer_prefix}-cost", 0, 23)
  location = var.resource_group_location
}

resource "azurerm_storage_account" "cost" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.current.name

  location                 = azurerm_resource_group.current.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "cost" {
  name                 = "cost"
  storage_account_name = azurerm_storage_account.cost.name
}

# Allow Stacklet to read the export from outside the subscription.
#
# Counter to Azure's own recommendation, we do not set `principal_type` or
# `skip_service_principal_aad_check`. Either one makes ARM skip the directory
# lookup on the principal. An invalid principal ID then yields a misleadingly
# clean apply that grants nothing.
#
# Without them, the provider reads an invalid ID as replication lag and retries
# for the whole create timeout, which defaults to 30 minutes. The override
# below cuts that down, with room to spare for real replication lag.
resource "azurerm_role_assignment" "stacklet_cost_reader" {
  scope                = azurerm_storage_account.cost.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.stacklet_principal_id

  timeouts {
    create = "5m"
  }
}

# The azurerm schema requires both recurrence dates, and Azure rejects a start
# date it considers stale: an export write carrying an old start fails with
# "updated 'from' value cannot be in the past". So the start has to be current
# every time the module writes the export, and it cannot come from the clock in
# the configuration, because a value derived from timestamp() stays unknown
# until apply and leaves every plan dirty. This resource holds the start in
# state, renews it once half the window passes, and takes a fresh one from
# either trigger below.
resource "time_rotating" "export_window_start" {
  rotation_months = local.export_renewal_months

  triggers = {
    # The storage location is ForceNew on the export, so a change there makes
    # Terraform create the export again rather than update it.
    storage_location = azurerm_storage_container.cost.id

    # A window change rewrites both dates on the export. Measured from a start
    # left alone, the new end date lands in the past for any window shorter
    # than the age of the deployment, which stops the export without an error.
    window_years = tostring(var.export_window_years)
  }
}

resource "azurerm_subscription_cost_management_export" "cost" {
  name                         = local.storage_account_name
  subscription_id              = data.azurerm_subscription.current.id
  recurrence_type              = "Daily"
  recurrence_period_start_date = time_rotating.export_window_start.rfc3339
  recurrence_period_end_date   = local.export_window_end

  export_data_storage_location {
    container_id     = azurerm_storage_container.cost.resource_manager_id
    root_folder_path = "/cost"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }
}

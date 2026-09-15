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
    # Terraform create the export again rather than update it. Mirror the exact
    # attribute the export keys on below. The container also exposes a
    # data-plane `id`, which names only the account and the container, so it
    # holds still through a resource group or subscription change that moves
    # the ARM id and replaces the export.
    storage_location = azurerm_storage_container.cost.resource_manager_id

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

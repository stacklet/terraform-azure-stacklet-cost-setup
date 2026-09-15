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

resource "azurerm_subscription_cost_management_export" "cost" {
  name                         = local.storage_account_name
  subscription_id              = data.azurerm_subscription.current.id
  recurrence_type              = "Daily"
  recurrence_period_start_date = timestamp()
  recurrence_period_end_date   = timeadd(timestamp(), "87600h")

  export_data_storage_location {
    container_id     = azurerm_storage_container.cost.resource_manager_id
    root_folder_path = "/cost"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }
}

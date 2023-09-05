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

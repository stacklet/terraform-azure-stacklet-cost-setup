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

# Stacklet reads the export from outside this subscription, so the grant belongs
# in the same apply that creates the storage account. Without it the export runs
# and writes successfully while Stacklet sees nothing, and the apply gives no
# sign of the gap. We scope it to the storage account rather than the container,
# to match the manual path in the Stacklet documentation.
#
# We leave principal_type unset, and skip_service_principal_aad_check with it,
# because both set the same field. Azure reads that field as an assertion that
# the principal exists and skips the directory lookup, so a caller who passes
# the application (client) ID instead of the object ID gets a role assignment
# that grants nothing, from a clean apply. Azure's own PrincipalNotFound message
# recommends setting it. Do not. A grant that silently covers no one is the
# failure this resource exists to prevent.
#
# The cost is that a wrong object ID looks like replication lag to the provider,
# which retries PrincipalNotFound for the whole create timeout. That timeout
# defaults to 30 minutes, hence the override below. Five minutes is far longer
# than a new service principal needs to replicate, and short enough that a typo
# reads as a failure rather than a hang.
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

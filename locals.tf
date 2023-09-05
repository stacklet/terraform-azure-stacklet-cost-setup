resource "random_string" "storage_account_suffix" {
  special = false
  length  = 24
  lower   = true
  upper   = false
}

locals {
  buckets = {
    "azure" : {
      "storage_account" : azurerm_storage_account.cost.name
      "storage_container" : azurerm_storage_container.cost.id
      "subscription_id" : data.azurerm_subscription.current.subscription_id
    }
  }
  storage_account_name = substr("stackletcost${random_string.storage_account_suffix.id}", 0, 23)
}

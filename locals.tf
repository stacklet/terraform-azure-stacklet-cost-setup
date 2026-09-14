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
      # Built from the blob endpoint rather than read off
      # azurerm_storage_container.cost.id. That attribute holds the same URL
      # today, but only because this container uses storage_account_name. A
      # container that uses storage_account_id gets the Resource Manager ID
      # there instead. The blob endpoint means the same thing under both.
      "container_url" : "${azurerm_storage_account.cost.primary_blob_endpoint}${azurerm_storage_container.cost.name}"
      "subscription_id" : data.azurerm_subscription.current.subscription_id
    }
  }
  storage_account_name = substr("stackletcost${random_string.storage_account_suffix.id}", 0, 23)
}

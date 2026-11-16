output "storage_account" {
  description = "Name of the Storage Account holding the cost export."
  value       = azurerm_storage_account.cost.name
}

output "container_url" {
  description = "URL of the container the cost export writes to."

  # Built from the blob endpoint rather than read off
  # azurerm_storage_container.cost.id, which holds the same URL today only
  # because this container uses storage_account_name. One that uses
  # storage_account_id gets the Resource Manager ID there instead.
  value = "${azurerm_storage_account.cost.primary_blob_endpoint}${azurerm_storage_container.cost.name}"
}

output "subscription_id" {
  description = "ID of the subscription the cost data covers."
  value       = data.azurerm_subscription.current.subscription_id
}

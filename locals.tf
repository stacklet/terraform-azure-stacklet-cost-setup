resource "random_string" "storage_account_suffix" {
  special = false
  length  = 24
  lower   = true
  upper   = false
}

locals {
  # Renewing at half the window leaves the export the other half to run on, so
  # an operator who applies the module only now and then still never finds it
  # expired. Renewal needs a run: the time provider proposes it during a plan,
  # and nothing renews an export that no one applies.
  #
  # Counted in months because half an odd window is not a whole number of years.
  # Rounding down would renew earlier than the README says it does.
  export_renewal_months = var.export_window_years * 6

  # A second time provider resource would hold the end date against a base that
  # Terraform plans to replace, and the two disagree during a run that both
  # renews the window and changes it. Deriving the end date keeps one
  # source for both dates. timeadd() has no year unit, and the leap days this
  # drops off the window do not matter against a renewal at half of it.
  export_window_end = timeadd(time_rotating.export_window_start.rfc3339, "${var.export_window_years * 8760}h")

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

resource "random_string" "storage_account_suffix" {
  special = false
  length  = 24
  lower   = true
  upper   = false
}

locals {
  # Renewing at half the window leaves the other half to run on, so a deployment
  # applied only now and then never finds the export expired. Nothing renews one
  # that no-one applies: the time provider proposes the renewal during a plan.
  #
  # Counted in months because half an odd window is not a whole number of years,
  # and rounding down would renew earlier than the README says it does.
  export_renewal_months = var.export_window_years * 6

  # Derived rather than held in a second time provider resource, which would
  # hold the end against a base Terraform plans to replace and disagree with it
  # during a run that both renews the window and changes it. timeadd() has no
  # year unit, and the leap days this drops do not matter against a renewal at
  # half the window.
  export_window_end = timeadd(time_rotating.export_window_start.rfc3339, "${var.export_window_years * 8760}h")

  # Everything the export carries apart from its schedule, split out so that
  # time_rotating can hash it. See the triggers on that resource.
  export_shape = {
    format = "Csv"

    # One CSV per run, which is the layout Stacklet reads. This is the default
    # at this api-version, written out rather than left implicit because
    # ENG-9630 has to flip it: the api-version it moves to rejects false.
    partitionData = false

    definition = {
      type      = "ActualCost"
      timeframe = "MonthToDate"
    }

    deliveryInfo = {
      destination = {
        resourceId = azurerm_storage_account.cost.id
        container  = azurerm_storage_container.cost.name

        # The leading slash is deliberate: Azure keeps it in the blob name
        # rather than resolving it away, so an export that drops it writes under
        # a prefix no earlier export used. Stacklet walks the container from its
        # root and reads the two prefixes as separate exports, double-counting
        # the month such a change lands in.
        rootFolderPath = "/cost"
      }
    }
  }

  buckets = {
    "azure" : {
      "storage_account" : azurerm_storage_account.cost.name
      # Built from the blob endpoint rather than read off
      # azurerm_storage_container.cost.id, which holds the same URL today only
      # because this container uses storage_account_name. One that uses
      # storage_account_id gets the Resource Manager ID there instead.
      "container_url" : "${azurerm_storage_account.cost.primary_blob_endpoint}${azurerm_storage_container.cost.name}"
      "subscription_id" : data.azurerm_subscription.current.subscription_id
    }
  }
  storage_account_name = substr("stackletcost${random_string.storage_account_suffix.id}", 0, 23)
}

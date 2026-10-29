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

  allow_nested_items_to_be_public = false

  # The account keys grant full read and write access to the cost data and
  # bypass Entra ID, so any principal that can call listKeys reaches customer
  # billing detail whatever data-plane roles it holds. The export identity below
  # is what makes disabling them possible.
  #
  # Disabling them constrains the caller too. The azurerm provider reaches a
  # storage account over the data plane with an access key, so every plan,
  # apply and destroy against this one fails with
  # `403 KeyBasedAuthenticationNotPermitted` unless the caller sets
  # `storage_use_azuread = true`. The README covers this for the caller.
  shared_access_key_enabled = false
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
  scope                = "${azurerm_storage_account.cost.id}/blobServices/default/containers/${azurerm_storage_container.cost.name}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.stacklet_principal_id

  timeouts {
    create = "5m"
  }
}

# An active schedule must carry both recurrence dates, at either api-version:
# "Missing schedule recurrencePeriod for active schedule". The API also rejects
# an end date in the past, and a start date more than about a day in the past,
# on a create and an update alike.
#
# The start therefore has to be stable rather than current, and it cannot come
# from the clock in the configuration, because a value derived from timestamp()
# stays unknown until apply and leaves every plan dirty. This resource holds the
# start in state and renews it once half the window passes, which keeps the end
# date derived from it ahead of now.
resource "time_rotating" "export_window_start" {
  rotation_months = local.export_renewal_months

  triggers = {
    # A window change rewrites both dates on the export. Measured from a start
    # left alone, the new end date lands in the past for any window shorter than
    # the age of the deployment, and the apply fails on the rule above. Rotating
    # on this trigger moves the start up so the new end date lands ahead of now.
    window_years = tostring(var.export_window_years)

    # Any other change to the export sends the whole body back, start date
    # included. That start has not moved since the deployment was created, and
    # the API refuses one more than about a day old, so without this a
    # deployment older than a day could not be changed at all. Rotating on the
    # shape of the body moves the start up whenever the rest of the export
    # changes. The schedule stays out of the hash, because the start feeds it.
    export_shape = sha256(jsonencode(local.export_shape))
  }
}

# Written through azapi rather than azurerm because the export needs a
# system-assigned identity, and no azurerm cost management export resource
# exposes `identity` or `location`. hashicorp/terraform-provider-azurerm#30253
# adds them and was still open as of 2026-10, so there is no azurerm path to
# this today.
#
# The api-version is 2023-08-01. Moving it forward changes where and how the
# data lands, which Stacklet has to handle first. ENG-9630 carries that work
# and the findings behind it.
#
# ARM rejects `"type": "None"` on this resource, answering `Identity Type None
# is not supported, supported value: SystemAssigned`, so an export cannot drop
# its identity once it has one. Removing the identity means deleting the export.
resource "azapi_resource" "cost_export" {
  type      = "Microsoft.CostManagement/exports@2023-08-01"
  name      = local.storage_account_name
  parent_id = data.azurerm_subscription.current.id
  location  = azurerm_resource_group.current.location

  # Cost Management grants this identity write access on the container when the
  # export is written, so the module needs no role assignment for it.
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = merge(local.export_shape, {
      schedule = {
        status     = "Active"
        recurrence = "Daily"
        recurrencePeriod = {
          from = time_rotating.export_window_start.rfc3339
          to   = local.export_window_end
        }
      }
    })
  }
}

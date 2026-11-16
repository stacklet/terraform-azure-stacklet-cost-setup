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

  # Account keys bypass Entra ID and carry full read and write access to the
  # cost data, so any principal that can call listKeys reaches customer billing
  # detail whatever data-plane roles it holds. The export identity below is what
  # lets them be disabled.
  #
  # The caller pays for it: azurerm reads a storage account over the data plane
  # with an access key, so every plan, apply and destroy fails with
  # `403 KeyBasedAuthenticationNotPermitted` without `storage_use_azuread = true`.
  shared_access_key_enabled = false
}

resource "azurerm_storage_container" "cost" {
  name                 = "cost"
  storage_account_name = azurerm_storage_account.cost.name
}

# Allow Stacklet to read the export from outside the subscription.
#
# Deliberately omits `principal_type` and `skip_service_principal_aad_check`,
# counter to Azure's own recommendation: either one makes ARM skip the directory
# lookup, so an invalid principal ID yields a clean apply that grants nothing.
# The cost is that the provider then reads an invalid ID as replication lag and
# retries for the full 30-minute create timeout, hence the override below.
resource "azurerm_role_assignment" "stacklet_cost_reader" {
  # Built by hand rather than read off azurerm_storage_container.cost.resource_manager_id,
  # which holds the same string but is deprecated and goes away in azurerm 5.0.
  scope                = "${azurerm_storage_account.cost.id}/blobServices/default/containers/${azurerm_storage_container.cost.name}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.stacklet_principal_id

  timeouts {
    create = "5m"
  }
}

# Holds the export's start date in state, renewed once half the window passes so
# that the end date derived from it stays ahead of now.
#
# An active schedule must carry both recurrence dates, at either api-version
# ("Missing schedule recurrencePeriod for active schedule"), and the API rejects
# an end date in the past and a start more than about a day old, on create and
# update alike. The start therefore has to be stable rather than current, and it
# cannot come from the clock: a value derived from timestamp() stays unknown
# until apply and leaves every plan dirty.
resource "time_rotating" "export_window_start" {
  rotation_months = local.export_renewal_months

  triggers = {
    # A window change rewrites both dates. Measured from a start left alone, the
    # new end date lands in the past for any window shorter than the age of the
    # deployment, and the apply fails on the rule above.
    window_years = tostring(var.export_window_years)

    # Any other change sends the whole body back, start date included. Without
    # this, a deployment older than a day could not be changed at all, because
    # its stored start is older than the API accepts. The schedule stays out of
    # the hash, because the start feeds it.
    export_shape = sha256(jsonencode(local.export_shape))
  }
}

# azapi rather than azurerm because the export needs a system-assigned identity,
# and no azurerm cost management export resource exposes `identity` or
# `location`. hashicorp/terraform-provider-azurerm#30253 adds them and was still
# open as of 2026-10.
#
# Moving the api-version forward changes where and how the data lands, which
# Stacklet has to handle first. ENG-9630 carries that work.
#
# An export cannot drop its identity once it has one: ARM rejects
# `"type": "None"` with `Identity Type None is not supported, supported value:
# SystemAssigned`. Removing it means deleting the export.
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

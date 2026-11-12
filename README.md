# terraform-azure-stacklet-cost-setup

Azure Cost Management export setup for Stacklet customers.

This module configures one Azure subscription to export its cost data to a
Storage Account, in the format that the Stacklet platform reads. The platform
runs outside the subscription, so the module also grants read access on the
container holding the export to a service principal that you create and that
Stacklet authenticates as.

For background, and for the steps to do the same thing through the Azure
portal, see the Stacklet documentation.

## Overview

This module creates the following in a single subscription:

* a Resource Group that holds the resources below
* a Storage Account for the cost management exports, with anonymous blob access
  and shared key access both disabled
* a container in that Storage Account for the export to write to
* a daily Cost Management export job that writes to the Storage Account under a
  system-assigned managed identity
* a Storage Blob Data Reader assignment on the container for Stacklet

Apply it once for each subscription whose costs you want available in Stacklet.

## Prerequisites

**Owner on the subscription**, or Contributor paired with Role Based Access
Control Administrator or User Access Administrator. The module assigns a role on
the container it creates, which Contributor alone cannot do.

**An Entra ID service principal for Stacklet** in your tenant. The Stacklet
documentation has the steps. Pass its object ID, not its Client ID, as
`stacklet_principal_id`:

```
az ad sp show --id <client-id> --query id -o tsv
```

Keep its Tenant ID, Client ID, and Client Secret as well. Those go to Stacklet
separately, and this module never sees them.

**The subscription registered with the `Microsoft.CostManagementExports`
resource provider**, which an export delivering to a storage account by resource
ID needs. Register the subscription that holds the Storage Account, once for
each one you apply this module to. Creating an export through the Azure portal
registers the provider as a side effect, so a subscription that has had one is
already registered:

```
az provider show -n Microsoft.CostManagementExports --query registrationState -o tsv \
  --subscription <subscription-id>
az provider register -n Microsoft.CostManagementExports --subscription <subscription-id>
```

An apply against an unregistered subscription fails on the export with
`RP Not Registered. Register destination storage account subscription with
Microsoft.CostManagementExports.`

**An `azapi` provider and `storage_use_azuread = true`** in the root module that
calls this one. The examples below show both.

## Usage examples

This module does not configure providers. The calling module must configure the
`azurerm` and `azapi` providers with the target subscription. azurerm 4.0 and
later require `subscription_id` on the provider block. The provider does not
read the subscription that `az login` selected.

The module is published to the [Terraform Registry](https://registry.terraform.io/modules/stacklet/stacklet-cost-setup/azure).
Set `source` to the registry address and pin `version` to a release.

### One subscription

```hcl
terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = "your-subscription-id"
  storage_use_azuread = true
}

provider "azapi" {
  subscription_id = "your-subscription-id"
}

module "azure_cost_setup" {
  source  = "stacklet/stacklet-cost-setup/azure"
  version = "2.0.0"

  customer_prefix         = "your-prefix"
  resource_group_location = "eastus"
  stacklet_principal_id   = "00000000-0000-0000-0000-000000000000"
}

# terraform output reports the root module only, so forward what you want to read.
output "storage_account" {
  value = module.azure_cost_setup.storage_account
}

output "container_url" {
  value = module.azure_cost_setup.container_url
}

output "subscription_id" {
  value = module.azure_cost_setup.subscription_id
}
```

### Several subscriptions in one root module

Apply the module once per subscription. Give each subscription an aliased
provider and pass that provider to the module:

```hcl
terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = "management-subscription-id"
  storage_use_azuread = true
}

provider "azurerm" {
  features {}
  alias               = "workload"
  subscription_id     = "workload-subscription-id"
  storage_use_azuread = true
}

provider "azapi" {
  subscription_id = "management-subscription-id"
}

provider "azapi" {
  alias           = "workload"
  subscription_id = "workload-subscription-id"
}

module "azure_cost_setup_workload" {
  source  = "stacklet/stacklet-cost-setup/azure"
  version = "2.0.0"

  providers = {
    azurerm = azurerm.workload
    azapi   = azapi.workload
  }

  customer_prefix         = "your-prefix"
  resource_group_location = "eastus"
  stacklet_principal_id   = "00000000-0000-0000-0000-000000000000"
}

# Every module block needs its own forwarding output.
output "azure_cost_setup_workload" {
  value = {
    storage_account = module.azure_cost_setup_workload.storage_account
    container_url   = module.azure_cost_setup_workload.container_url
    subscription_id = module.azure_cost_setup_workload.subscription_id
  }
}
```

One service principal can serve every subscription. Pass its object ID in each
module block. The module grants it read access on the export container in each
subscription.

Credentials come from the standard Azure authentication chain. For local use,
authenticate with `az login`. For automated deployments, supply credentials
through environment variables (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`,
`ARM_TENANT_ID`) or set `client_id`, `client_secret`, and `tenant_id` directly
on the provider block.

## What to send Stacklet

Run `terraform output` and send Stacklet every value the module returns, once
per subscription you applied it to. Send the service principal's Tenant ID,
Client ID, and Client Secret separately. You do not need to collect anything
from the portal.

## Upgrade notes

### Upgrading to 2.0.0

Steps 1 through 3 are configuration changes to make before running
`terraform plan`. Step 4 is a single apply.

**1. Set the module `version` to `2.0.0`.** If you are still on a pinned commit
rather than a released version, work through "Upgrading to 1.0.0" below first.

**2. Declare the `azapi` provider.** Add an `azapi` entry to your own
`required_providers` with `source = "azure/azapi"`, because `azapi` is not in
the `hashicorp` namespace and Terraform otherwise looks for it there and fails.
Add an `azapi` provider block, and add `azapi = azapi.<alias>` to the
`providers` map where your module block passes one. The examples under
"Usage examples" above show both layouts. Run `terraform init -upgrade`
afterwards.

**3. Set `storage_use_azuread = true`** on the `azurerm` provider. A plan does
not catch this one. Skip it and the apply fails after it has already destroyed
the old export, leaving the subscription exporting nothing until you add the
setting and apply again.

**4. Apply.** The apply disables anonymous blob access and shared key access on
the Storage Account, and the new export gets the write access it needs as part
of being created.

> **Warning:** reverting this upgrade cannot be done in place, because an
> export cannot drop its identity once it has one. Going back to an earlier
> release means deleting the export by hand before applying that release. As
> with the upgrade, the exported data is unchanged.

**What the upgrade changes.** The cost export now authenticates to the Storage
Account with a system-assigned managed identity, and the Storage Account
disables shared key access. Cost Management cannot write to an account with
shared key access disabled unless the export carries the identity, so the two
changes ship together.

The export also moves from the `azurerm` provider to `azapi`, due to limitations
in the former. The provider change forces replacement of the export, which loses
its run history but leaves the exported data intact. The plan reports both
halves:

```
# module.azure_cost_setup.azurerm_subscription_cost_management_export.cost will be destroyed
# module.azure_cost_setup.azapi_resource.cost_export will be created
```

Stacklet's role assignment moves from the Storage Account to the container, so
the plan replaces it too. Stacklet reads only the container, and the narrower
grant withholds the account-wide `generateUserDelegationKey` action that lets
its holder mint a shareable URL over the whole account.

The outputs change shape. Where there was one output named `output`, holding a
map with everything under an `azure` key, there are now three top-level outputs:
`storage_account`, `container_url` and `subscription_id`. A root module that
forwards `module.azure_cost_setup.output` has to name the values it wants
instead.

Cost Management does not run the export when it is created, so confirm the
upgrade by triggering a run rather than waiting a day for the first scheduled
one. See "Confirming that the export runs" under Troubleshooting.

### Upgrading to 1.0.0

1.0.0 is the first release, so whatever you have now is pinned to a commit
rather than to a version. Work through this section together with the 2.0.0
steps above and apply once, rather than applying 1.0.0 on the way: the end state
described here is 2.0.0's. Move `source` to the registry address and set
`version`, as shown above.

Read your current copy rather than a version number. If it declares its own
`azurerm` provider block, that is the block 1.0.0 removes. A root module that
supplied no provider relied on it. Add an `azurerm` provider block to your root
module and set `subscription_id` on it.

If you apply this repository directly from a checkout, azurerm now stops at plan
and asks for explicit configuration, because its `features` block has no
default. Consume the module from your own root module instead, as shown above.
That is the pattern this module is built for, and it keeps the provider
configuration with the caller who owns the subscription.

`stacklet_principal_id` is new and required, so an existing root module stops at
plan until you supply it. Pass the object ID of the principal you already granted
Storage Blob Data Reader by hand, if you granted one.

Applying 2.0.0 grants that role on the container. A grant you made at the Storage
Account carries a different scope, so the two do not collide and the apply
succeeds, leaving Stacklet with the wider of the two. Remove the one you made by
hand afterwards. A grant you made on the container itself does collide, and the
apply fails with `RoleAssignmentExists` until you import it:

```
terraform import module.azure_cost_setup.azurerm_role_assignment.stacklet_cost_reader \
  "<container-resource-id>/providers/Microsoft.Authorization/roleAssignments/<assignment-guid>"
```

## Troubleshooting

### Every plan and apply fails with `KeyBasedAuthenticationNotPermitted`

```
Error: encoding Storage Account ...: retrieving queue properties ...: 403
KeyBasedAuthenticationNotPermitted
```

Set `storage_use_azuread = true` on the `azurerm` provider. The Storage Account
disables shared key access, and the provider reaches both the account and its
container over the data plane, with an access key unless this redirects those
calls through Entra ID.

Set it before the first apply. Without it the first apply fails while creating
the Storage Account, and every later `terraform plan`, `apply` and `destroy`
fails the same way.

### An apply sits on the role assignment for minutes

The `stacklet_principal_id` is usually wrong. The object ID and the Client ID
are both GUIDs, so check which one you have. Azure rejects an ID that names no
principal, and a wrong one surfaces as `PrincipalNotFound` only after a
five-minute retry.

### An apply fails with `'from' value cannot be in the past`

Something changed the export outside Terraform, which leaves the module holding
a start date Azure no longer accepts. Deleting the export, recreating it, or
pausing it in the portal all have this effect: the next apply sends the stored
start back with the rest of the body and fails, whatever was actually edited.

That does not self-correct, because the resource to replace is the start date
rather than the export:

```
terraform apply -replace=module.azure_cost_setup.time_rotating.export_window_start
```

Use your own module block name. Terraform reports no changes rather than an
error when a `-replace` address matches nothing.

### Runs fail after the export's own grant is removed

Cost Management grants the export's identity write access on the container as
part of writing the export, and the module does not manage that assignment.
Remove it and the runs fail, while `terraform apply` reports no changes, because
nothing in the configuration has changed. A scheduled run does not restore it
either. Only another write to the export does:

```
terraform apply -replace=module.azure_cost_setup.azapi_resource.cost_export
```

### The cost export window

The Cost Management API requires an end date on a scheduled export, so the
module schedules a window rather than an open-ended export. `export_window_years`
sets its length, ten years by default.

An apply starts a fresh window, running the full length again from the time of
the apply, whenever any of these are true:

* half the window has passed
* `export_window_years` has changed
* anything else about the export has changed

The window does not renew itself. A deployment that goes unapplied from the
half-way point to the end date keeps exporting until that end date, then stops.
Applying again puts it back on schedule. Window rotation does not modify
existing cost data.

### Confirming that the export runs

Cost Management does not run the export when it is created, and the first
scheduled run lands about a day later. Trigger one by hand rather than waiting.
The export and the Storage Account share a name, so `<name>` below is the
`storage_account` output value:

```
az rest --method post --headers "Content-Length=0" \
  --url 'https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.CostManagement/exports/<name>/run?api-version=2023-08-01'
```

Poll the run history at the `runHistory` endpoint, which is a separate path from
`/run`:

```
az rest --method get \
  --url 'https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.CostManagement/exports/<name>/runHistory?api-version=2023-08-01'
```

A run passes through `Queued` and `InProgress` before it reaches `Completed`.
A run that cannot write to the Storage Account ends at `Failed`. Runs usually
finish in under a minute, but not always, so allow about twenty minutes before
treating one as stuck.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.12.0, < 3.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.8.1, < 4.0.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.10.0, < 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.12.0, < 3.0.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.8.1, < 4.0.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.10.0, < 1.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azapi_resource.cost_export](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_resource_group.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.stacklet_cost_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [random_string.storage_account_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_rotating.export_window_start](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/rotating) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_customer_prefix"></a> [customer\_prefix](#input\_customer\_prefix) | Stacklet provided customer prefix | `string` | n/a | yes |
| <a name="input_export_window_years"></a> [export\_window\_years](#input\_export\_window\_years) | Length in years of the cost export schedule. The module renews the window once half of it passes, and changing this forces a fresh window from the time of the apply. Renewal needs an apply to happen. See the cost export window note under Troubleshooting in the README. | `number` | `10` | no |
| <a name="input_resource_group_location"></a> [resource\_group\_location](#input\_resource\_group\_location) | Resource group deployment location | `string` | n/a | yes |
| <a name="input_stacklet_principal_id"></a> [stacklet\_principal\_id](#input\_stacklet\_principal\_id) | Object ID of the Entra ID service principal that Stacklet reads the cost export with. This is the service principal's object ID, not the application (client) ID of the app registration behind it. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_container_url"></a> [container\_url](#output\_container\_url) | URL of the container the cost export writes to. |
| <a name="output_storage_account"></a> [storage\_account](#output\_storage\_account) | Name of the Storage Account holding the cost export. |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | ID of the subscription the cost data covers. |
<!-- END_TF_DOCS -->

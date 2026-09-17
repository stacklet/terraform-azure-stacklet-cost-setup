# terraform-azure-stacklet-cost-setup

Azure Cost Management export setup for Stacklet customers.

This module configures one Azure subscription to export its cost data to a
Storage Account, in the format that the Stacklet platform reads. The platform
runs outside the subscription, so the module also grants read access on that
Storage Account to a service principal that you create and that Stacklet
authenticates as.

For background, and for the steps to do the same thing through the Azure
portal, see the Stacklet documentation.

## Overview

Apply this module once per subscription. The user or service principal that
applies it needs permission to create Cost Management exports, Storage
Accounts, and Resource Groups, and to assign roles on the Storage Account it
creates. Owner covers all of it. Contributor does not: it cannot assign roles,
and the apply fails at that step. Pair Contributor with Role Based Access
Control Administrator or User Access Administrator to keep the narrower grant.

The module creates:

* a Resource Group that holds the resources below
* a Storage Account for the cost management exports
* a daily Cost Management export job that writes to the Storage Account
* a Storage Blob Data Reader assignment on the Storage Account for Stacklet

The job exports in the format that Stacklet needs.

## Before you apply

Create an Entra ID service principal for Stacklet in your tenant. The Stacklet
documentation has the steps. Keep its Tenant ID, Client ID, and Client Secret,
and send those to Stacklet separately. This module never sees them.

The module needs the service principal's object ID:

```
az ad sp show --id <client-id> --query id -o tsv
```

Pass that as `stacklet_principal_id`. The object ID and the Client ID are both
GUIDs, and people swap them by mistake, so the module keeps the directory check
on. Azure rejects an ID that names no principal, and the apply fails rather than
record a grant that gives Stacklet nothing. A successful apply means the grant
landed on a real principal.

A wrong ID shows up as `PrincipalNotFound`. The provider cannot tell that apart
from replication lag on a new service principal, so it retries for five minutes
before it gives up. An apply that sits on the role assignment for minutes
usually means the ID is wrong, not that Azure is slow.

## What to send Stacklet

After the apply, `terraform output output` reports the storage account name,
the container URL, and the subscription ID. Those are what the documentation
asks you to hand over. You do not need to collect anything from the portal.

## Versioning

Releases carry a `vMAJOR.MINOR.PATCH` tag. Pin `source` to one:

```hcl
source = "github.com/stacklet/terraform-azure-stacklet-cost-setup?ref=v1.0.0"
```

A published tag keeps naming the same commit, because repository rules block
updates and deletions on `v*`. A tag is still a mutable pointer by nature, so
pin the commit itself if you would rather not rely on a repository setting. The
tag names the commit directly:

```
git ls-remote https://github.com/stacklet/terraform-azure-stacklet-cost-setup refs/tags/v1.0.0
```

A major bump means the root module that calls this one needs work before it
moves. Read the migration notes for that release first.

## Provider Configuration

This module does not configure providers. The calling module must configure
the `azurerm` provider with the target subscription. azurerm 4.0 and later
require `subscription_id` on the provider block. The provider does not read the
subscription that `az login` selected.

Credentials come from the standard Azure authentication chain. For local use,
authenticate with `az login`. For automated deployments, supply credentials
through environment variables (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`,
`ARM_TENANT_ID`) or set `client_id`, `client_secret`, and `tenant_id` directly
on the provider block.

### Standalone deployment

Applying the cost export to a single subscription:

```hcl
provider "azurerm" {
  features {}
  subscription_id = "your-subscription-id"
}

module "azure_cost_setup" {
  source = "github.com/stacklet/terraform-azure-stacklet-cost-setup?ref=v1.0.0"

  customer_prefix         = "your-prefix"
  resource_group_location = "eastus"
  stacklet_principal_id   = "00000000-0000-0000-0000-000000000000"
}
```

### Several subscriptions in one root module

Apply the module once per subscription. Give each subscription an aliased
provider and pass that provider to the module:

```hcl
provider "azurerm" {
  features {}
  subscription_id = "management-subscription-id"
}

provider "azurerm" {
  alias           = "workload"
  subscription_id = "workload-subscription-id"
  features {}
}

module "azure_cost_setup_workload" {
  source = "github.com/stacklet/terraform-azure-stacklet-cost-setup?ref=v1.0.0"

  providers = {
    azurerm = azurerm.workload
  }

  customer_prefix         = "your-prefix"
  resource_group_location = "eastus"
  stacklet_principal_id   = "00000000-0000-0000-0000-000000000000"
}
```

One service principal can serve every subscription. Pass its object ID in each
module block. The module grants it read access on each Storage Account it
creates.

## The cost export window

The `azurerm` provider requires an end date on a cost export, so the module
writes a window rather than an open-ended schedule. The window is ten years
long by default and the module renews it after five. Both come from
`export_window_years`. Renewal happens on the next plan and apply after the
half-way point, and it rewrites the dates on the export in place. Renewal does
not touch cost data already in the Storage Account.

If an apply does not happen between the half-way point and the expiration, the
export stops. Applying again puts it back on schedule. Changing
`export_window_years` also forces a fresh window from the time of the apply,
so a shorter window never lands in the past.

Deleting the export by hand, or recreating it outside a normal apply, leaves the
module holding a start date Azure no longer accepts, and the next apply fails
with `'from' value cannot be in the past`. That does not self-correct, because
the resource to replace is the start date rather than the export:

```
terraform apply -replace=module.azure_cost_setup.time_rotating.export_window_start
```

Use your own module block name. Terraform reports no changes rather than an
error when a `-replace` address matches nothing.

## Migrating to 1.0.0

1.0.0 is the first tagged release, so a copy pinned before it carries no version
number to compare against. Check that copy itself. If it declares its own
`azurerm` provider block, that is the block this release removes. A root module
that supplied no provider relied on it. Add an `azurerm` provider block to your
root module and set `subscription_id` on it.

If you apply this repository directly from a checkout, azurerm now stops at plan
and asks for explicit configuration, because its `features` block has no
default. Consume the module from your own root module instead, as shown above.
That is the pattern this module is built for, and it keeps the provider
configuration with the caller who owns the subscription.

`stacklet_principal_id` is new and required, so an existing root module stops at
plan until you supply it. If you already granted Stacklet Storage Blob Data
Reader by hand, pass the same principal's object ID and import the assignment
you made. Azure refuses a second assignment for the same principal, role, and
scope, so an apply without the import fails with `RoleAssignmentExists`:

```
terraform import module.azure_cost_setup.azurerm_role_assignment.stacklet_cost_reader \
  "<storage-account-resource-id>/providers/Microsoft.Authorization/roleAssignments/<assignment-guid>"
```

The `output` map also drops its `storage_container` key for `container_url`.
Despite its name, that key already held the container URL, so the value does not
change. Anything reading it needs a rename and nothing more.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.8.1, < 4.0.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.10.0, < 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.8.1, < 4.0.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.10.0, < 1.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.stacklet_cost_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_subscription_cost_management_export.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_cost_management_export) | resource |
| [random_string.storage_account_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_rotating.export_window_start](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/rotating) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_customer_prefix"></a> [customer\_prefix](#input\_customer\_prefix) | Stacklet provided customer prefix | `string` | n/a | yes |
| <a name="input_export_window_years"></a> [export\_window\_years](#input\_export\_window\_years) | Length in years of the cost export schedule. The module renews the window once half of it passes, and changing this forces a fresh window from the time of the apply. Renewal needs an apply to happen. See the cost export window section of the README. | `number` | `10` | no |
| <a name="input_resource_group_location"></a> [resource\_group\_location](#input\_resource\_group\_location) | Resource group deployment location | `string` | n/a | yes |
| <a name="input_stacklet_principal_id"></a> [stacklet\_principal\_id](#input\_stacklet\_principal\_id) | Object ID of the Entra ID service principal that Stacklet reads the cost export with. This is the service principal's object ID, not the application (client) ID of the app registration behind it. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_output"></a> [output](#output\_output) | n/a |
<!-- END_TF_DOCS -->

# terraform-azure-stacklet-cost-setup

Azure Cost Management export setup for Stacklet customers.

This module configures one Azure subscription to export its cost data to a
Storage Account, in the format that the Stacklet platform reads. The platform
runs outside the subscription and reads the export with credentials that you
give to Stacklet separately. This module does not grant that access.

For background, and for the steps to do the same thing through the Azure
portal, see the Stacklet documentation.

## Overview

Apply this module once per subscription. The user or service principal that
applies it needs permission to create Cost Management exports, Storage
Accounts, and Resource Groups.

The module creates:

* a Resource Group that holds the resources below
* a Storage Account for the cost management exports
* a daily Cost Management export job that writes to the Storage Account

The job exports in the format that Stacklet needs.

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

The common case, applying the cost export to a single subscription:

```hcl
provider "azurerm" {
  features {}
  subscription_id = "your-subscription-id"
}

module "azure_cost_setup" {
  source = "github.com/stacklet/terraform-azure-stacklet-cost-setup?ref=<sha>"

  customer_prefix         = "your-prefix"
  resource_group_location = "eastus"
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
  source = "github.com/stacklet/terraform-azure-stacklet-cost-setup?ref=<sha>"

  providers = {
    azurerm = azurerm.workload
  }

  customer_prefix         = "your-prefix"
  resource_group_location = "eastus"
}
```

## Migrating from a previous version

Earlier versions of this module declared an `azurerm` provider block, so a root
module that supplied no provider still worked. We removed that block. Add an
`azurerm` provider block to your root module and set `subscription_id` on it.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.56.0, < 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.8.1, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.56.0, < 5.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.8.1, < 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_storage_account.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_subscription_cost_management_export.cost](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_cost_management_export) | resource |
| [random_string.storage_account_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_customer_prefix"></a> [customer\_prefix](#input\_customer\_prefix) | Stacklet provided customer prefix | `string` | n/a | yes |
| <a name="input_resource_group_location"></a> [resource\_group\_location](#input\_resource\_group\_location) | Resource group deployment location | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_output"></a> [output](#output\_output) | n/a |
<!-- END_TF_DOCS -->

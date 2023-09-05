# terraform-azure-stacklet-cost-setup
Cost and Usage Report (CUR) setup for Stacklet customers

This repository provides automation for setting up a CUR in your organizational account in such a way that the Stacklet platform, running in a different account, can access and use the CUR data.

More background information, along with instructions for accomplishing the same thing via the AWS console, can be found in the Stacklet documentation.

## Azure

### Overview

The terraform in this repository is meant to be applied in each subscription, independent of any account in which the Stacklet platform is running, and must be applied by a user or service principal that has permissions to create Cost Management exports, storage accounts, and resource groups. Stacklet utilizes credentials provided in Stacklet to read from the created Storage Account.

It does the following:

* Creates a Resource Group to contain all created resources
* Creates a Storage Account to store cost management exports
* Creates a Cost Management export job to push data into the Storage Account

This setup ensures that the Cost Management export is in the format required by Stacklet.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

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

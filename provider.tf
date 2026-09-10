# This module declares no provider blocks, so that the caller can configure and
# alias the providers it passes in.
#
# We constrain the providers to the majors this module works against. azurerm
# deprecates `storage_account_name` and `resource_manager_id` on
# azurerm_storage_container. Version 5.0 removes them, so this module needs
# changes before it supports that major. Do not widen these constraints without
# a test against the new major.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.56.0, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.8.1, < 4.0.0"
    }
  }
  required_version = ">= 1.9.0, < 2.0.0"
}

# This module declares no provider blocks, so that the caller can configure and
# alias the providers it passes in.
#
# We constrain the providers to the majors this module works against. azurerm
# deprecates `storage_account_name` and `resource_manager_id` on
# azurerm_storage_container. Version 5.0 removes them, so this module needs
# changes before it supports that major. Do not widen these constraints without
# a test against the new major.
#
# The azurerm floor is 4.0.0 because that release made `subscription_id` a
# required provider property, which is what the caller now has to supply. That
# is plan-time behavior rather than schema, so `terraform validate` cannot see
# it: the CI floor job proves these versions still match the schema, not that
# 4.0.0 is the correct floor. Change it against the provider changelog, not on
# the strength of a green build.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.8.1, < 4.0.0"
    }
  }
  required_version = ">= 1.9.0, < 2.0.0"
}

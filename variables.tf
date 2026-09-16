variable "customer_prefix" {
  type        = string
  description = "Stacklet provided customer prefix"
}

variable "resource_group_location" {
  type        = string
  description = "Resource group deployment location"
}

variable "stacklet_principal_id" {
  type        = string
  description = "Object ID of the Entra ID service principal that Stacklet reads the cost export with. This is the service principal's object ID, not the application (client) ID of the app registration behind it."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.stacklet_principal_id))
    error_message = "The stacklet_principal_id value must be a GUID. Read the object ID with `az ad sp show --id <client-id> --query id -o tsv`."
  }
}

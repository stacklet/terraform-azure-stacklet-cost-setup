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

variable "export_window_years" {
  type        = number
  default     = 10
  description = "Length in years of the cost export schedule. The module renews the window once half of it passes, so this is not a deadline to track. A change starts a fresh window from the time of the apply."

  validation {
    condition     = var.export_window_years >= 2 && var.export_window_years == floor(var.export_window_years)
    error_message = "The export window must be a whole number of years, and at least 2."
  }
}

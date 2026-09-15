variable "customer_prefix" {
  type        = string
  description = "Stacklet provided customer prefix"
}

variable "resource_group_location" {
  type        = string
  description = "Resource group deployment location"
}

variable "export_window_years" {
  type        = number
  default     = 10
  description = "Length in years of the cost export schedule. The module renews the window once half of it passes, so this is not a deadline to track. A change starts a fresh window from the time of the apply."

  validation {
    # 292 years is the ceiling. timeadd takes hours, and Go rejects the 293 year
    # equivalent outright: `invalid duration "2566680h"`.
    condition     = var.export_window_years >= 2 && var.export_window_years <= 292 && var.export_window_years == floor(var.export_window_years)
    error_message = "The export window must be a whole number of years, from 2 to 292."
  }
}

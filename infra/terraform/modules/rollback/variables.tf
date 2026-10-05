variable "name_prefix" {
  type = string
}

variable "name_suffix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  description = "Resource group for the tests, alerts and Automation account (shared RG)"
  type        = string
}

variable "tags" {
  type = map(string)
}

variable "app_insights_id" {
  type = string
}

variable "backends" {
  description = "Backend apps to protect: { cin = { app_id, app_name, resource_group_name, hostname } }"
  type = map(object({
    app_id              = string
    app_name            = string
    resource_group_name = string
    hostname            = string
  }))
}

variable "runbook_content" {
  description = "PowerShell content of scripts/rollback/Invoke-AutoRollback.ps1"
  type        = string
}

variable "notify_email" {
  description = "Optional email for alert notifications (null = none)"
  type        = string
  default     = null
}

variable "failed_location_threshold" {
  description = "How many of the 5 test locations must fail before the alert fires"
  type        = number
  default     = 2
}

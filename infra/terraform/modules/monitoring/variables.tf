variable "name_prefix" {
  description = "Prefix for resource names, e.g. task6"
  type        = string
}

variable "name_suffix" {
  description = "Random suffix for globally unique names"
  type        = string
}

variable "location" {
  description = "Azure region for the monitoring resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the monitoring resources"
  type        = string
}

variable "retention_in_days" {
  description = "Log Analytics retention"
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 = unlimited). Lab cost safety net."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags applied to every resource (required by Azure Policy)"
  type        = map(string)
}

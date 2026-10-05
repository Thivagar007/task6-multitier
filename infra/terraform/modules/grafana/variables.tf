variable "name" {
  description = "Azure Managed Grafana name (2-23 chars, letters/numbers/dashes, globally unique)"
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "grafana_major_version" {
  description = "Grafana major version supported by Azure Managed Grafana (Standard SKU currently accepts 12 or 13)"
  type        = string
  default     = "12"
}

variable "reader_scopes" {
  description = "Scopes (resource group IDs) Grafana may READ metrics/logs from"
  type        = map(string)
}

variable "admin_object_id" {
  description = "Object ID of the user who gets Grafana Admin (you)"
  type        = string
}

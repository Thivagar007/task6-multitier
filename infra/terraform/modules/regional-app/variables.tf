# ---------- Placement / naming ----------
variable "region_key" {
  description = "Short region key used in names, e.g. cin or sin"
  type        = string
}

variable "location" {
  description = "Azure region, e.g. centralindia"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for this region's plan and apps"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names, e.g. task6"
  type        = string
}

variable "name_suffix" {
  description = "Random suffix for globally unique app names"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource (required by Azure Policy)"
  type        = map(string)
}

# ---------- Plan + autoscale ----------
variable "sku_name" {
  description = "App Service plan SKU. S1 = cheapest tier with slots + autoscale."
  type        = string
  default     = "S1"
}

variable "autoscale_min" {
  description = "Minimum instance count"
  type        = number
  default     = 1
}

variable "autoscale_max" {
  description = "Maximum instance count"
  type        = number
  default     = 3
}

variable "autoscale_default" {
  description = "Instance count when metrics are unavailable"
  type        = number
  default     = 1
}

# ---------- Backend identity + dependencies ----------
variable "backend_identity_id" {
  description = "Resource ID of the backend user-assigned managed identity"
  type        = string
}

variable "backend_identity_client_id" {
  description = "Client ID of the backend identity (AZURE_CLIENT_ID app setting)"
  type        = string
}

variable "key_vault_uri" {
  type = string
}

variable "storage_account_url" {
  type = string
}

variable "storage_container_name" {
  type = string
}

variable "sql_server_fqdn" {
  type = string
}

variable "sql_database_name" {
  type = string
}

# ---------- Monitoring ----------
variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "log_analytics_workspace_id" {
  type = string
}

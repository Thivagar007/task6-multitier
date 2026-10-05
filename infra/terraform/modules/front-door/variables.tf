variable "name_prefix" {
  type = string
}

variable "name_suffix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "sku_name" {
  description = "Standard_AzureFrontDoor (custom WAF rules) or Premium_AzureFrontDoor (+ managed OWASP/DRS + bot rules)"
  type        = string
  default     = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku_name)
    error_message = "sku_name must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "origins" {
  description = "Regional frontends: { cin = { host_name = ..., weight = 80 } }"
  type = map(object({
    host_name = string
    weight    = number
  }))
}

variable "rate_limit_per_minute" {
  description = "WAF: max requests per client IP per minute before blocking"
  type        = number
  default     = 300
}

variable "log_analytics_workspace_id" {
  type = string
}

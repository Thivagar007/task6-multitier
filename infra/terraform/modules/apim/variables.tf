variable "name" {
  type = string
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

variable "sku_name" {
  description = "Developer_1 = full features, no SLA, cheapest dedicated tier"
  type        = string
  default     = "Developer_1"
}

variable "publisher_name" {
  type = string
}

variable "publisher_email" {
  description = "Required by APIM; receives system notifications"
  type        = string
}

variable "backend_url" {
  description = "Base URL APIM forwards to (the Traffic Manager profile)"
  type        = string
}

variable "api_policy_xml" {
  description = "Rendered API-level policy (apim/policies/orders-api-policy.xml)"
  type        = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "operations" {
  description = "GET operations exposed by the API: { key = url_template }"
  type        = map(string)
  default = {
    info   = "/api/info"
    health = "/api/health"
    orders = "/api/orders"
    config = "/api/config"
    files  = "/api/files"
    load   = "/api/load"
    slow   = "/api/slow"
    error  = "/api/error"
  }
}

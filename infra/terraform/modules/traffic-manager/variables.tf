variable "name" {
  description = "Profile name; also the DNS label -> <name>.trafficmanager.net"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  description = "Tags applied to every resource (required by Azure Policy)"
  type        = map(string)
}

variable "endpoints" {
  description = "Azure endpoints keyed by region: { cin = { target_resource_id = ..., weight = 80 } }"
  type = map(object({
    target_resource_id = string
    weight             = number
  }))
}

variable "dns_ttl" {
  description = "DNS TTL in seconds. Low = traffic shifts fast and the split is easy to observe."
  type        = number
  default     = 10
}

variable "probe_path" {
  description = "Health endpoint Traffic Manager probes on every endpoint"
  type        = string
  default     = "/api/health"
}

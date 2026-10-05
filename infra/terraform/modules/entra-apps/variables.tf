variable "name_prefix" {
  description = "Prefix for display names, e.g. task6"
  type        = string
}

variable "name_suffix" {
  type = string
}

variable "spa_redirect_uris" {
  description = "Where the React app is served (each region, Front Door, localhost). MSAL redirects back here after sign-in."
  type        = list(string)
}

variable "scope_name" {
  description = "Delegated permission (scope) the API exposes"
  type        = string
  default     = "Orders.Read"
}

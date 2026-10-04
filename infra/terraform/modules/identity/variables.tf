variable "name" {
  description = "Name of the user-assigned managed identity"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the identity"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource (required by Azure Policy)"
  type        = map(string)
}

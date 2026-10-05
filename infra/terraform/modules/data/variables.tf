variable "name_prefix" {
  description = "Prefix for resource names, e.g. task6"
  type        = string
}

variable "name_suffix" {
  description = "Random suffix for globally unique names"
  type        = string
}

variable "location" {
  description = "Azure region for Key Vault, Storage and SQL"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the data services"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource (required by Azure Policy)"
  type        = map(string)
}

variable "deployer_object_id" {
  description = "Object ID of whoever runs Terraform (you). Becomes SQL Entra admin and gets data-plane rights to seed the secret and sample blob."
  type        = string
}

variable "deployer_login" {
  description = "Display label for the SQL Entra admin (any text, e.g. your UPN)"
  type        = string
}

variable "backend_principal_id" {
  description = "Principal (object) ID of the backend user-assigned managed identity"
  type        = string
}

variable "allowed_client_ip" {
  description = "Your public IP, allowed through the SQL firewall so you can run the setup script. null = no rule."
  type        = string
  default     = null
}

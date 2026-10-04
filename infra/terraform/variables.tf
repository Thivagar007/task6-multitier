variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "project" {
  description = "Short project name used in resource names"
  type        = string
  default     = "task6"
}

variable "primary_location" {
  description = "Primary region (gets the higher Traffic Manager weight)"
  type        = string
  default     = "centralindia"
}

variable "secondary_location" {
  description = "Secondary region"
  type        = string
  default     = "southindia"
}

variable "tags" {
  description = "Tags required by Azure Policy on every resource group and resource"
  type        = map(string)
  default = {
    environment   = "dev"
    owner         = "thivagarraja"
    "cost-center" = "training"
  }
}

variable "deployer_login" {
  description = "Label for the SQL Entra admin (your email/UPN)"
  type        = string
}

variable "allowed_client_ip" {
  description = "Your public IP for the SQL firewall (to run the setup script). null = no rule."
  type        = string
  default     = null
}

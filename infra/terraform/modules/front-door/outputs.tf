output "endpoint_hostname" {
  description = "fde-...azurefd.net - the public entry point for users"
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "profile_id" {
  value = azurerm_cdn_frontdoor_profile.this.id
}

output "profile_name" {
  value = azurerm_cdn_frontdoor_profile.this.name
}

output "waf_policy_name" {
  value = azurerm_cdn_frontdoor_firewall_policy.this.name
}

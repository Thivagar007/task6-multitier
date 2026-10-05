output "profile_id" {
  value = azurerm_traffic_manager_profile.this.id
}

output "profile_name" {
  value = azurerm_traffic_manager_profile.this.name
}

output "fqdn" {
  description = "<name>.trafficmanager.net - APIM uses this as its backend"
  value       = azurerm_traffic_manager_profile.this.fqdn
}

output "gateway_url" {
  value = azurerm_api_management.this.gateway_url
}

output "api_base_url" {
  description = "VITE_API_BASE_URL for the React build"
  value       = "${azurerm_api_management.this.gateway_url}/${azurerm_api_management_api.orders.path}"
}

output "name" {
  value = azurerm_api_management.this.name
}

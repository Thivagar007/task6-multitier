output "name" {
  value = azurerm_dashboard_grafana.this.name
}

output "endpoint" {
  description = "Grafana URL - sign in with your Entra ID account"
  value       = azurerm_dashboard_grafana.this.endpoint
}

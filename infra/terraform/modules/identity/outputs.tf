output "id" {
  description = "Resource ID - attach to App Service (identity block)"
  value       = azurerm_user_assigned_identity.this.id
}

output "client_id" {
  description = "Client ID - goes into the AZURE_CLIENT_ID app setting"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Object ID - used for role assignments and the SQL user"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "name" {
  value = azurerm_user_assigned_identity.this.name
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Goes into the backend KEY_VAULT_URI app setting"
  value       = azurerm_key_vault.this.vault_uri
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "storage_account_url" {
  description = "Goes into the backend STORAGE_ACCOUNT_URL app setting"
  value       = trimsuffix(azurerm_storage_account.this.primary_blob_endpoint, "/")
}

output "storage_container_name" {
  value = azurerm_storage_container.documents.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.this.name
}

output "sql_server_fqdn" {
  description = "Goes into the backend SQL_SERVER app setting"
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Goes into the backend SQL_DATABASE app setting"
  value       = azurerm_mssql_database.this.name
}

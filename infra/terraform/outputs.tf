output "resource_groups" {
  value = merge(
    { shared = azurerm_resource_group.shared.name },
    { for k, rg in azurerm_resource_group.region : k => rg.name }
  )
}

output "name_suffix" {
  value = local.suffix
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

output "app_insights_name" {
  value = module.monitoring.app_insights_name
}

output "app_insights_connection_string" {
  value     = module.monitoring.app_insights_connection_string
  sensitive = true
}

output "backend_identity_client_id" {
  description = "Goes into the AZURE_CLIENT_ID app setting of the backend"
  value       = module.backend_identity.client_id
}

output "backend_identity_principal_id" {
  description = "Object ID used for role assignments and the SQL user"
  value       = module.backend_identity.principal_id
}

output "key_vault_uri" {
  value = module.data.key_vault_uri
}

output "storage_account_url" {
  value = module.data.storage_account_url
}

output "sql_server_fqdn" {
  value = module.data.sql_server_fqdn
}

output "sql_database_name" {
  value = module.data.sql_database_name
}

output "apps" {
  description = "Per-region app names and hostnames"
  value = {
    for k, r in module.region : k => {
      backend          = r.backend_name
      backend_url      = "https://${r.backend_hostname}"
      backend_staging  = "https://${r.backend_staging_hostname}"
      frontend         = r.frontend_name
      frontend_url     = "https://${r.frontend_hostname}"
      frontend_staging = "https://${r.frontend_staging_hostname}"
    }
  }
}

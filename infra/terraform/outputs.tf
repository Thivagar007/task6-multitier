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

output "traffic_manager_fqdn" {
  value = module.traffic_manager.fqdn
}

output "apim_api_base_url" {
  description = "VITE_API_BASE_URL"
  value       = module.apim.api_base_url
}

output "entra" {
  description = "Values for the React build (.env.production) and token tests"
  value = {
    tenant_id     = module.entra.tenant_id
    spa_client_id = module.entra.spa_client_id
    api_client_id = module.entra.api_client_id
    api_scope     = module.entra.api_scope
  }
}

output "front_door_url" {
  description = "Public entry point for users"
  value       = "https://${module.front_door.endpoint_hostname}"
}

output "rollback" {
  value = {
    automation_account = module.rollback.automation_account_name
    web_tests          = module.rollback.web_test_names
    alerts             = module.rollback.alert_names
  }
}

output "grafana_url" {
  value = module.grafana.endpoint
}

output "grafana_name" {
  value = module.grafana.name
}

output "frontend_custom_domain_verification_ids" {
  description = "TXT record values (asuid.<sub>) needed before adding a custom domain"
  value       = { for k, m in module.region : k => m.frontend_custom_domain_verification_id }
  sensitive   = true
}

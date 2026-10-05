output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "api_client_id" {
  description = "Audience (aud) APIM expects in the token"
  value       = azuread_application.api.client_id
}

output "api_scope" {
  description = "Full scope string the SPA / CLI requests"
  value       = "api://${azuread_application.api.client_id}/${var.scope_name}"
}

output "scope_name" {
  value = var.scope_name
}

output "spa_client_id" {
  description = "VITE_AAD_CLIENT_ID for the React build"
  value       = azuread_application.spa.client_id
}

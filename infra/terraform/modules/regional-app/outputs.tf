output "service_plan_id" {
  value = azurerm_service_plan.this.id
}

output "backend_name" {
  value = azurerm_linux_web_app.backend.name
}

output "backend_id" {
  description = "Used as a Traffic Manager Azure endpoint"
  value       = azurerm_linux_web_app.backend.id
}

output "backend_hostname" {
  value = azurerm_linux_web_app.backend.default_hostname
}

output "backend_staging_hostname" {
  value = azurerm_linux_web_app_slot.backend_staging.default_hostname
}

output "frontend_name" {
  value = azurerm_linux_web_app.frontend.name
}

output "frontend_id" {
  value = azurerm_linux_web_app.frontend.id
}

output "frontend_hostname" {
  description = "Used as a Front Door origin"
  value       = azurerm_linux_web_app.frontend.default_hostname
}

output "frontend_staging_hostname" {
  value = azurerm_linux_web_app_slot.frontend_staging.default_hostname
}

output "frontend_custom_domain_verification_id" {
  description = "Value for the asuid.<sub> TXT record when adding a custom domain"
  value       = azurerm_linux_web_app.frontend.custom_domain_verification_id
  sensitive   = true
}

output "frontend_custom_domain" {
  value = var.custom_domain
}

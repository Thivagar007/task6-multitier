# =====================================================================
# OPTIONAL: custom domain + FREE App Service managed certificate
#
# App Service only issues managed certificates for a CUSTOM domain you
# own. The default *.azurewebsites.net hostnames are already served over
# HTTPS with Microsoft's wildcard certificate, so nothing is created here
# while var.custom_domain is null (the lab default - no domain).
#
# To enable (e.g. app.example.com on the frontend):
#   1. DNS:  CNAME  app                -> <frontend default hostname>
#            TXT    asuid.app          -> output "frontend_custom_domain_verification_id"
#   2. tfvars: frontend_custom_domains = { cin = "app.example.com" }
#   3. terraform apply  -> hostname binding -> managed cert -> SNI binding
# Managed certs auto-renew; https_only + TLS 1.2 still apply.
# =====================================================================

resource "azurerm_app_service_custom_hostname_binding" "frontend" {
  count = var.custom_domain == null ? 0 : 1

  hostname            = var.custom_domain
  app_service_name    = azurerm_linux_web_app.frontend.name
  resource_group_name = var.resource_group_name

  # The certificate binding below manages SSL; don't fight it here.
  lifecycle {
    ignore_changes = [ssl_state, thumbprint]
  }
}

# FREE App Service managed certificate.
# Created with azapi because azurerm_app_service_managed_certificate does not
# send tags in the create request, so the "require environment/owner/
# cost-center tags" policy denies it (403 RequestDisallowedByPolicy).
locals {
  # "/subscriptions/<id>/resourceGroups/<rg>" taken from the plan's ID
  rg_id = join("/", slice(split("/", azurerm_service_plan.this.id), 0, 5))
}

resource "azapi_resource" "managed_certificate" {
  count = var.custom_domain == null ? 0 : 1

  type      = "Microsoft.Web/certificates@2023-12-01"
  name      = var.custom_domain
  parent_id = local.rg_id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      canonicalName = var.custom_domain          # => managed (free) certificate
      serverFarmId  = azurerm_service_plan.this.id
    }
  }

  response_export_values = ["properties.thumbprint", "properties.expirationDate", "properties.issuer"]

  # The hostname must be bound (and DNS-validated) before Azure issues the cert
  depends_on = [azurerm_app_service_custom_hostname_binding.frontend]

  timeouts {
    create = "30m"
  }
}

resource "azurerm_app_service_certificate_binding" "frontend" {
  count = var.custom_domain == null ? 0 : 1

  hostname_binding_id = azurerm_app_service_custom_hostname_binding.frontend[0].id
  certificate_id      = azapi_resource.managed_certificate[0].id
  ssl_state           = "SniEnabled"
}

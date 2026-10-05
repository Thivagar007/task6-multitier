# =====================================================================
# Module: apim
#   API Management in front of the backend:
#     - API "orders" at https://<apim>.azure-api.net/orders/...
#     - backend entity -> Traffic Manager (weighted 80/20 regions)
#     - API policy: CORS, Azure AD validate-jwt (OAuth 2.0), rate limit
#     - gateway logs -> Log Analytics
# =====================================================================

resource "azurerm_api_management" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.sku_name
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Backend entity: where APIM sends requests
resource "azurerm_api_management_backend" "orders" {
  name                = "orders-tm-backend"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = var.backend_url
  description         = "Traffic Manager profile (weighted across regional backends)"

  tls {
    validate_certificate_chain = true
    # LAB TRADE-OFF: the app presents *.azurewebsites.net but APIM connects to
    # *.trafficmanager.net. In production use a custom domain + matching cert
    # on the backends and set this to true.
    validate_certificate_name = false
  }
}

resource "azurerm_api_management_api" "orders" {
  name                  = "orders-api"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  display_name          = "Orders API"
  path                  = "orders"
  protocols             = ["https"]
  revision              = "1"
  subscription_required = false # access is controlled by the Azure AD token instead
}

resource "azurerm_api_management_api_operation" "get" {
  for_each = var.operations

  operation_id        = each.key
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "GET ${each.value}"
  method              = "GET"
  url_template        = each.value
}

resource "azurerm_api_management_api_policy" "orders" {
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  xml_content         = var.api_policy_xml

  depends_on = [azurerm_api_management_backend.orders]
}

resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_api_management.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "GatewayLogs" # every API call: status, latency, caller IP
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

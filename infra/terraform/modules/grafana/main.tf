# =====================================================================
# Module: grafana  (Azure Managed Grafana)
#
#   - System-assigned managed identity -> "Monitoring Reader" on the
#     task's resource groups (read-only, no secrets anywhere)
#   - The built-in "Azure Monitor" data source uses that identity to
#     query Application Insights / Log Analytics / metrics
#   - You get "Grafana Admin" via Entra ID sign-in
#
#   Dashboard: grafana/orders-dashboard.json (imported with az grafana)
# =====================================================================

resource "azurerm_dashboard_grafana" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Standard"
  grafana_major_version         = var.grafana_major_version
  api_key_enabled               = false # no API keys - Entra ID only
  public_network_access_enabled = true
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Least privilege: Grafana can only READ monitoring data in these RGs
resource "azurerm_role_assignment" "monitoring_reader" {
  for_each = var.reader_scopes

  scope                = each.value
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

# You: full admin inside Grafana (sign in with your Entra ID account)
resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.admin_object_id
}

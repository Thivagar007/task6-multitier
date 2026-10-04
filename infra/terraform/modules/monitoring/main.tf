# =====================================================================
# Module: monitoring
#   Log Analytics workspace (all logs) + workspace-based Application Insights
# =====================================================================

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.name_prefix}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  daily_quota_gb      = var.daily_quota_gb
  tags                = var.tags
}

# Workspace-based: telemetry lands in the workspace above, so Grafana/KQL
# can query requests, dependencies and availability results in one place.
resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name_prefix}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

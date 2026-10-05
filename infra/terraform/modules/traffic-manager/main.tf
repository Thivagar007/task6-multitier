# =====================================================================
# Module: traffic-manager
#   DNS-based WEIGHTED routing across the regional backends.
#
#   Client/APIM resolves <name>.trafficmanager.net
#     -> Traffic Manager answers with a CNAME to ONE healthy backend,
#        chosen at random in proportion to the weights (80 / 20)
#     -> client then talks to that backend directly
#
#   Health probes hit /api/health on every endpoint; an endpoint that
#   fails is removed from DNS answers automatically (built-in failover).
# =====================================================================

resource "azurerm_traffic_manager_profile" "this" {
  name                   = var.name
  resource_group_name    = var.resource_group_name
  traffic_routing_method = "Weighted"
  tags                   = var.tags

  dns_config {
    relative_name = var.name
    ttl           = var.dns_ttl
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = var.probe_path
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
    expected_status_code_ranges  = ["200-299"]
  }
}

resource "azurerm_traffic_manager_azure_endpoint" "this" {
  for_each = var.endpoints

  name               = "ep-${each.key}"
  profile_id         = azurerm_traffic_manager_profile.this.id
  target_resource_id = each.value.target_resource_id
  weight             = each.value.weight
}

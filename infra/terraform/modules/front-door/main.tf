# =====================================================================
# Module: front-door  (Azure Front Door Standard/Premium = CDN + WAF)
#
#   User -> Front Door edge (nearest POP, TLS, WAF, cache)
#        -> origin group: both regional frontends (weighted 80/20,
#           health-probed; unhealthy region is skipped automatically)
#
#   Routes:
#     /assets/*  cached + compressed at the edge (Vite file names are
#                content-hashed, so caching them is always safe)
#     /*         NOT cached (index.html must always be fresh after a deploy)
#
#   WAF (Prevention mode):
#     custom rules (Standard + Premium): per-IP rate limit, block common
#                                        XSS / SQL-injection probes
#     managed rules (Premium only):      Microsoft Default Rule Set + Bot Manager
# =====================================================================

locals {
  is_premium = var.sku_name == "Premium_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                     = "afd-${var.name_prefix}-${var.name_suffix}"
  resource_group_name      = var.resource_group_name
  sku_name                 = var.sku_name
  response_timeout_seconds = 60
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "fde-${var.name_prefix}-${var.name_suffix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

# ---------------------------------------------------------------------
# Origins: the regional React frontends
# ---------------------------------------------------------------------
resource "azurerm_cdn_frontdoor_origin_group" "web" {
  name                     = "og-web"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    protocol            = "Https"
    path                = "/"
    request_type        = "GET"
    interval_in_seconds = 60
  }
}

resource "azurerm_cdn_frontdoor_origin" "web" {
  for_each = var.origins

  name                           = "origin-${each.key}"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.web.id
  enabled                        = true
  host_name                      = each.value.host_name
  origin_host_header             = each.value.host_name # App Service routes by Host header
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true
  priority                       = 1
  weight                         = each.value.weight
}

# ---------------------------------------------------------------------
# Routes (CDN behaviour)
# ---------------------------------------------------------------------
resource "azurerm_cdn_frontdoor_route" "assets" {
  name                          = "route-assets-cached"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web.id
  cdn_frontdoor_origin_ids      = [for o in azurerm_cdn_frontdoor_origin.web : o.id]

  patterns_to_match      = ["/assets/*"]
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true # HTTP -> HTTPS at the edge
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress = [
      "application/javascript",
      "text/javascript",
      "text/css",
      "image/svg+xml",
      "application/json",
    ]
  }
}

resource "azurerm_cdn_frontdoor_route" "app" {
  name                          = "route-app"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web.id
  cdn_frontdoor_origin_ids      = [for o in azurerm_cdn_frontdoor_origin.web : o.id]

  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  # no cache block = not cached (index.html always fresh)

  depends_on = [azurerm_cdn_frontdoor_route.assets]
}

# ---------------------------------------------------------------------
# WAF policy (name must be letters/numbers only)
# ---------------------------------------------------------------------
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                              = "waf${var.name_prefix}${var.name_suffix}"
  resource_group_name               = var.resource_group_name
  sku_name                          = var.sku_name
  enabled                           = true
  mode                              = "Prevention" # block, not just log
  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode("<html><body><h1>403 - Request blocked by Azure Front Door WAF</h1></body></html>")
  tags                              = var.tags

  # Rule 1: rate limiting per client IP
  custom_rule {
    name                           = "RateLimitPerIP"
    enabled                        = true
    priority                       = 1
    type                           = "RateLimitRule"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = var.rate_limit_per_minute
    action                         = "Block"

    match_condition {
      match_variable = "RemoteAddr"
      operator       = "IPMatch"
      match_values   = ["0.0.0.0/0", "::/0"] # applies to every client
    }
  }

  # Rule 2: block common XSS / SQL-injection probes in the query string
  custom_rule {
    name     = "BlockXssSqliProbes"
    enabled  = true
    priority = 2
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable = "QueryString"
      operator       = "Contains"
      match_values   = ["<script", "javascript:", "union select", "' or 1=1", "../"]
      transforms     = ["Lowercase", "UrlDecode"]
    }
  }

  # Premium only: Microsoft-managed OWASP-style rules + bot protection
  dynamic "managed_rule" {
    for_each = local.is_premium ? [
      { type = "Microsoft_DefaultRuleSet", version = "2.1" },
      { type = "Microsoft_BotManagerRuleSet", version = "1.1" },
    ] : []
    content {
      type    = managed_rule.value.type
      version = managed_rule.value.version
      action  = "Block"
    }
  }
}

# Attach the WAF policy to the endpoint (all paths)
resource "azurerm_cdn_frontdoor_security_policy" "waf" {
  name                     = "secpol-waf"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

# ---------------------------------------------------------------------
# Logs: access log (cache hit/miss, POP, latency), health probes, WAF blocks
# ---------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "afd" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_cdn_frontdoor_profile.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "FrontDoorAccessLog"
  }
  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }
  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

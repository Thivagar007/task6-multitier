# =====================================================================
# Module: regional-app  (called once per region with for_each)
#
#   App Service plan (Linux, S1)
#     ├─ backend  (Node.js API)  + "staging" slot   ← blue/green
#     ├─ frontend (React, pm2)   + "staging" slot   ← blue/green
#     ├─ autoscale: CPU % and HTTP queue length
#     └─ diagnostic settings -> Log Analytics
#
#   Slot settings:
#     APP_SLOT      sticky  -> each slot always reports its own name
#     APP_VERSION   swaps   -> travels with the code (set by the pipeline)
#     FAIL_HEALTH   swaps   -> rollback demo: a "bad release" carries it
#                              into production on swap
# =====================================================================

locals {
  base = "${var.name_prefix}-${var.region_key}-${var.name_suffix}"

  # Settings shared by backend production + staging (APP_SLOT added per slot)
  backend_settings = {
    APP_REGION                            = var.location
    APP_VERSION                           = "0.0.0" # overwritten by each deploy
    FAIL_HEALTH                           = "false"
    AZURE_CLIENT_ID                       = var.backend_identity_client_id
    KEY_VAULT_URI                         = var.key_vault_uri
    STORAGE_ACCOUNT_URL                   = var.storage_account_url
    STORAGE_CONTAINER                     = var.storage_container_name
    SQL_SERVER                            = var.sql_server_fqdn
    SQL_DATABASE                          = var.sql_database_name
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true" # npm install on the server during zip deploy
  }

  frontend_settings = {
    APP_REGION                     = var.location
    SCM_DO_BUILD_DURING_DEPLOYMENT = "false" # we deploy the already-built dist/ folder
  }

  # Values the pipeline / rollback demo change at runtime - Terraform must not revert them
  runtime_managed = ["APP_VERSION", "FAIL_HEALTH"]
}

# ---------------------------------------------------------------------
# App Service plan
# ---------------------------------------------------------------------
resource "azurerm_service_plan" "this" {
  name                = "asp-${local.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.sku_name
  tags                = var.tags
}

# ---------------------------------------------------------------------
# Backend (Node.js API) - production slot
# ---------------------------------------------------------------------
resource "azurerm_linux_web_app" "backend" {
  name                = "app-${var.name_prefix}-api-${var.region_key}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true
  tags                = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.backend_identity_id]
  }

  site_config {
    always_on                         = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    health_check_path                 = "/api/health"
    health_check_eviction_time_in_min = 5

    application_stack {
      node_version = "22-lts"
    }
  }

  app_settings = merge(local.backend_settings, { APP_SLOT = "production" })

  sticky_settings {
    app_setting_names = ["APP_SLOT"]
  }

  lifecycle {
    ignore_changes = [
      app_settings["APP_VERSION"],
      app_settings["FAIL_HEALTH"],
      # Added by the Azure portal when App Insights is opened from the app blade
      tags["hidden-link: /app-insights-resource-id"],
    ]
  }
}

# Backend - staging slot (new versions land here first)
resource "azurerm_linux_web_app_slot" "backend_staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.backend.id
  https_only     = true
  tags           = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.backend_identity_id]
  }

  site_config {
    always_on                         = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    health_check_path                 = "/api/health"
    health_check_eviction_time_in_min = 5

    application_stack {
      node_version = "22-lts"
    }
  }

  app_settings = merge(local.backend_settings, { APP_SLOT = "staging" })

  lifecycle {
    ignore_changes = [
      app_settings["APP_VERSION"],
      app_settings["FAIL_HEALTH"],
      # Added by the Azure portal when App Insights is opened from the app blade
      tags["hidden-link: /app-insights-resource-id"],
    ]
  }
}

# ---------------------------------------------------------------------
# Frontend (React static build served by pm2) - production slot
# ---------------------------------------------------------------------
resource "azurerm_linux_web_app" "frontend" {
  name                = "app-${var.name_prefix}-web-${var.region_key}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true
  tags                = var.tags

  site_config {
    always_on           = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
    http2_enabled       = true
    # Serve dist/ as a single-page app (unknown paths fall back to index.html)
    app_command_line = "pm2 serve /home/site/wwwroot --no-daemon --spa"

    application_stack {
      node_version = "22-lts"
    }
  }

  app_settings = merge(local.frontend_settings, { APP_SLOT = "production" })

  sticky_settings {
    app_setting_names = ["APP_SLOT"]
  }
}

# Frontend - staging slot
resource "azurerm_linux_web_app_slot" "frontend_staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.frontend.id
  https_only     = true
  tags           = var.tags

  site_config {
    always_on           = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
    http2_enabled       = true
    app_command_line    = "pm2 serve /home/site/wwwroot --no-daemon --spa"

    application_stack {
      node_version = "22-lts"
    }
  }

  app_settings = merge(local.frontend_settings, { APP_SLOT = "staging" })
}

# ---------------------------------------------------------------------
# Autoscale (on the PLAN - all apps in the plan scale together)
#   Scale OUT when ANY out-rule fires; scale IN only when ALL in-rules agree
# ---------------------------------------------------------------------
resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${local.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_service_plan.this.id
  tags                = var.tags

  profile {
    name = "default"

    capacity {
      default = var.autoscale_default
      minimum = var.autoscale_min
      maximum = var.autoscale_max
    }

    # OUT: average CPU > 70% over 5 minutes -> +1 instance
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # OUT: HTTP queue length > 10 (requests waiting for a worker) -> +1 instance
    rule {
      metric_trigger {
        metric_name        = "HttpQueueLength"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 10
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # IN: average CPU < 30% over 10 minutes -> -1 instance
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    # IN: HTTP queue length < 2 over 10 minutes -> -1 instance
    rule {
      metric_trigger {
        metric_name        = "HttpQueueLength"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 2
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

# ---------------------------------------------------------------------
# Diagnostic settings -> Log Analytics (resource-specific tables)
# ---------------------------------------------------------------------
locals {
  diag_targets = {
    backend  = azurerm_linux_web_app.backend.id
    frontend = azurerm_linux_web_app.frontend.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "apps" {
  for_each = local.diag_targets

  # App Service logs always land in resource-specific tables (AppServiceHTTPLogs...),
  # so log_analytics_destination_type is not set: Azure does not store it for
  # App Service and Terraform would show a change on every plan.
  name                       = "diag-to-law"
  target_resource_id         = each.value
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs" # every request: status, latency, client IP
  }
  enabled_log {
    category = "AppServiceConsoleLogs" # stdout/stderr from Node.js
  }
  enabled_log {
    category = "AppServicePlatformLogs" # container start/stop, swaps
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics" # CPU, memory, HTTP queue length
  }
}

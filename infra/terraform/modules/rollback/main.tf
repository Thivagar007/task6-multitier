# =====================================================================
# Module: rollback  -  automated rollback driven by availability tests
#
#   App Insights standard web test  (5 locations, every 5 min,
#   GET https://<backend>/api/health, expect 200)
#        | 2+ locations fail
#        v
#   Metric alert (severity 1)  --->  Action group
#                                       |  webhook (common alert schema)
#                                       v
#   Automation runbook  (managed identity, Website Contributor on the app)
#        -> checks staging (previous release) is healthy
#        -> Switch-AzWebAppSlot staging <-> production   == ROLLBACK
#
#   One test + alert + action group + webhook per region.
# =====================================================================

# ---------------------------------------------------------------------
# 1. Availability tests (production slot of each backend)
# ---------------------------------------------------------------------
resource "azurerm_application_insights_standard_web_test" "health" {
  for_each = var.backends

  name                    = "webtest-health-${each.key}"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = var.app_insights_id
  description             = "Probes ${each.value.app_name} /api/health; failures trigger automatic rollback"
  frequency               = 300 # seconds
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true

  # Microsoft test agent locations (5 = recommended minimum)
  geo_locations = [
    "apac-sg-sin-azr",  # Southeast Asia
    "apac-hk-hkn-azr",  # East Asia
    "apac-jp-kaw-edge", # Japan East
    "emea-nl-ams-azr",  # West Europe
    "us-va-ash-azr",    # East US
  ]

  request {
    url       = "https://${each.value.hostname}/api/health"
    http_verb = "GET"
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }

  # The test is linked to App Insights via application_insights_id.
  # (Azure did not keep a "hidden-link" tag here, so we don't set one.)
  tags = var.tags
}

# ---------------------------------------------------------------------
# 2. Automation account + runbook (the rollback "robot")
# ---------------------------------------------------------------------
resource "azurerm_automation_account" "this" {
  name                = "aa-${var.name_prefix}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Least privilege: can manage (swap) ONLY the backend apps
resource "azurerm_role_assignment" "automation_swap" {
  for_each = var.backends

  scope                = each.value.app_id
  role_definition_name = "Website Contributor"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
}

resource "azurerm_automation_runbook" "rollback" {
  name                    = "Invoke-AutoRollback"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  runbook_type            = "PowerShell72"
  log_progress            = true
  log_verbose             = false
  description             = "Swaps staging back into production when the availability alert fires"
  content                 = var.runbook_content
  tags                    = var.tags

  # Azure reports PowerShell 7.2 runbooks back as "PowerShell", which would
  # force a delete/recreate (and break the webhooks) on every plan.
  lifecycle {
    ignore_changes = [runbook_type]
  }
}

# Webhook URLs must have an expiry; 1 year is plenty for this project
resource "time_offset" "webhook_expiry" {
  offset_years = 1
}

resource "azurerm_automation_webhook" "rollback" {
  for_each = var.backends

  name                    = "wh-rollback-${each.key}"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.rollback.name
  expiry_time             = time_offset.webhook_expiry.rfc3339
  enabled                 = true

  # Which app this webhook rolls back
  parameters = {
    resourcegroup = each.value.resource_group_name
    appname       = each.value.app_name
  }
}

# ---------------------------------------------------------------------
# 3. Action groups + alerts
# ---------------------------------------------------------------------
resource "azurerm_monitor_action_group" "rollback" {
  for_each = var.backends

  name                = "ag-rollback-${each.key}"
  resource_group_name = var.resource_group_name
  short_name          = "rollback${each.key}" # max 12 chars
  tags                = var.tags

  webhook_receiver {
    name                    = "automation-rollback-runbook"
    service_uri             = azurerm_automation_webhook.rollback[each.key].uri
    use_common_alert_schema = true
  }

  dynamic "email_receiver" {
    for_each = var.notify_email == null ? [] : [var.notify_email]
    content {
      name                    = "notify-owner"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  for_each = var.backends

  name                = "alert-availability-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights_standard_web_test.health[each.key].id, var.app_insights_id]
  description         = "Availability of ${each.value.app_name} dropped -> automatic slot rollback"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = var.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.health[each.key].id
    component_id          = var.app_insights_id
    failed_location_count = var.failed_location_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.rollback[each.key].id
  }
}

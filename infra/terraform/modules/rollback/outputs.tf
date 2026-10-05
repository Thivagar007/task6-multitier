output "automation_account_name" {
  value = azurerm_automation_account.this.name
}

output "web_test_names" {
  value = { for k, t in azurerm_application_insights_standard_web_test.health : k => t.name }
}

output "alert_names" {
  value = { for k, a in azurerm_monitor_metric_alert.availability : k => a.name }
}

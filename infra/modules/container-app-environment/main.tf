resource "azurerm_container_app_environment" "main" {
  name                           = var.name
  location                       = var.location
  resource_group_name            = var.resource_group_name
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  infrastructure_subnet_id       = var.infrastructure_subnet_id
  internal_load_balancer_enabled = true

  workload_profile {
    # Name must be <16 characters; provided via variable
    name                  = var.workload_profile_name
    workload_profile_type = var.workload_profile_type
    minimum_count         = 1
    maximum_count         = 3
  }

  tags = var.tags
}

# Diagnostic Settings for Container App Environment
resource "azurerm_monitor_diagnostic_setting" "containerappenv" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

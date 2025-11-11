resource "azurerm_container_app_environment" "main" {
  name                           = var.name
  location                       = var.location
  resource_group_name            = var.resource_group_name
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  infrastructure_subnet_id       = var.infrastructure_subnet_id
  internal_load_balancer_enabled = true

  workload_profile {
    name                  = "gitlab-dedicated"
    workload_profile_type = "Dedicated"
    minimum_count         = 1
    maximum_count         = 3
  }

  tags = var.tags
}

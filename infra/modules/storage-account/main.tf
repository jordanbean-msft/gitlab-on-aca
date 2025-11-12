resource "azurerm_storage_account" "main" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Premium" # Hard-coded: NFS requires Premium FileStorage
  account_replication_type      = var.account_replication_type
  account_kind                  = "FileStorage"
  tags                          = var.tags
  https_traffic_only_enabled    = false # Must be disabled for NFS mounts
  public_network_access_enabled = false
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "Transaction"
    enabled  = true
  }
}

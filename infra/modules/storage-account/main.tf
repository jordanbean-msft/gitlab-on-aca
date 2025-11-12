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

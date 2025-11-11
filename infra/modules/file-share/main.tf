resource "azurerm_storage_share" "main" {
  name                 = var.name
  storage_account_name = var.storage_account_name # Deprecated attribute may be replaced with new resource in future versions
  quota                = var.quota
  enabled_protocol     = "NFS"
}

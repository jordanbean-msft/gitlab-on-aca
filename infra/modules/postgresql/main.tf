resource "azurerm_postgresql_flexible_server" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  version                       = var.postgresql_version
  public_network_access_enabled = var.public_network_access_enabled

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  sku_name     = var.sku_name
  storage_mb   = var.storage_mb
  storage_tier = var.storage_tier

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  dynamic "high_availability" {
    for_each = var.high_availability_mode == "Disabled" ? [] : [var.high_availability_mode]
    content {
      mode = high_availability.value
    }
  }

  zone = var.zone
}

resource "azurerm_postgresql_flexible_server_configuration" "work_mem" {
  name      = "work_mem"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "8192" # 8 MB in KB
}

resource "azurerm_postgresql_flexible_server_configuration" "maintenance_work_mem" {
  name      = "maintenance_work_mem"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "65536" # 64 MB in KB
}

resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "400"
}

resource "azurerm_postgresql_flexible_server_configuration" "shared_buffers" {
  name      = "shared_buffers"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "524288" # 2 GB in 8KB pages (2*1024*1024/8)
}

resource "azurerm_postgresql_flexible_server_configuration" "statement_timeout" {
  name      = "statement_timeout"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "60000" # 60 seconds in milliseconds
}

resource "azurerm_postgresql_flexible_server_database" "gitlabhq_production" {
  name      = "gitlabhq_production"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Required PostgreSQL extensions for GitLab
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "btree_gist,pg_trgm,plpgsql"
}

# Diagnostic Settings for PostgreSQL Flexible Server
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # PostgreSQL Flexible Server Metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }

  # PostgreSQL Flexible Server Logs
  enabled_log {
    category = "PostgreSQLLogs"
  }

  enabled_log {
    category = "PostgreSQLFlexDatabaseXacts"
  }

  enabled_log {
    category = "PostgreSQLFlexQueryStoreRuntime"
  }

  enabled_log {
    category = "PostgreSQLFlexQueryStoreWaitStats"
  }

  enabled_log {
    category = "PostgreSQLFlexSessions"
  }

  enabled_log {
    category = "PostgreSQLFlexTableStats"
  }
}

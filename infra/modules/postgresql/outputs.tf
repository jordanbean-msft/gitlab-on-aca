output "id" {
  description = "PostgreSQL Flexible Server ID"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "name" {
  description = "PostgreSQL Flexible Server name"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "fqdn" {
  description = "PostgreSQL Flexible Server FQDN"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "database_name" {
  description = "GitLab database name"
  value       = azurerm_postgresql_flexible_server_database.gitlabhq_production.name
}

output "administrator_login" {
  description = "Administrator login name"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

output "container_apps_nsg_id" { value = azurerm_network_security_group.container_apps.id }
output "private_endpoints_nsg_id" { value = azurerm_network_security_group.private_endpoints.id }

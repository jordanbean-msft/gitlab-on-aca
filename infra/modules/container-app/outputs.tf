output "id" { value = azurerm_container_app.main.id }
output "name" { value = azurerm_container_app.main.name }
output "fqdn" { value = azurerm_container_app.main.ingress[0].fqdn }
output "latest_revision_name" { value = azurerm_container_app.main.latest_revision_name }

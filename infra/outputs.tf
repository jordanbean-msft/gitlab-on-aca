########## Root Outputs for GitLab on Azure Container Apps ##########

output "gitlab_url" {
  description = "GitLab Container App FQDN"
  value       = "https://${module.gitlab_app.fqdn}"
}

output "gitlab_fqdn" {
  description = "Container App FQDN"
  value       = module.gitlab_app.fqdn
}

output "acr_name" {
  description = "Azure Container Registry name"
  value       = module.acr.name
}

output "acr_login_server" {
  description = "Azure Container Registry login server"
  value       = module.acr.login_server
}

output "storage_account_name" {
  description = "Storage account name"
  value       = module.storage_account.name
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = module.key_vault.name
}

output "container_app_environment_id" {
  description = "Container App Environment ID"
  value       = module.container_app_environment.id
}

output "unique_suffix" {
  description = "Generated unique suffix for resource naming"
  value       = local.unique_suffix
}

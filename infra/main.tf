########## Root Main Configuration for GitLab on Azure Container Apps ##########

# Data source for current subscription tenant ID
data "azurerm_client_config" "current" {}

locals {
  base_tags = merge(
    var.tags,
    {
      managed_by = "terraform"
      project    = "gitlab-on-aca"
    }
  )
}

########## Foundation Module (Unique Suffix) ##########
module "foundation" {
  source = "./modules/foundation"
}

locals {
  unique_suffix = module.foundation.unique_suffix
}

########## Network Module (NSG Configuration) ##########
module "network" {
  source                      = "./modules/network"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  unique_suffix               = local.unique_suffix
  container_apps_subnet_id    = var.container_apps_subnet_id
  private_endpoints_subnet_id = var.private_endpoints_subnet_id
  tags                        = local.base_tags
}

########## Identity Module (Managed Identity) ##########
module "identity" {
  source              = "./modules/identity"
  name                = "uami-gitlab-${local.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.base_tags
}

########## Log Analytics & App Insights ##########
module "log_analytics" {
  source              = "./modules/log-analytics"
  name                = "law-gitlab-${local.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  retention_in_days   = 30
  tags                = local.base_tags
}

module "app_insights" {
  source              = "./modules/app-insights"
  name                = "appi-gitlab-${local.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = module.log_analytics.id
  application_type    = "web"
  tags                = local.base_tags
}

########## Azure Container Registry ##########
module "acr" {
  source              = "./modules/acr"
  name                = "acrgitlab${local.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  pull_principal_id   = module.identity.principal_id
  tags                = local.base_tags
}

########## Key Vault ##########
module "key_vault" {
  source              = "./modules/key-vault"
  name                = "kv-gitlab-${local.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.base_tags
}

# Grant Terraform identity access to create secrets
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant azd executing principal Key Vault Administrator
resource "azurerm_role_assignment" "azd_kv_admin" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.azure_principal_id
  depends_on           = [module.key_vault]
}

# Wait for RBAC permissions to propagate
resource "time_sleep" "wait_for_rbac" {
  create_duration = "60s"
  depends_on = [azurerm_role_assignment.terraform_kv_admin, azurerm_role_assignment.azd_kv_admin]
}

# Store GitLab secrets in Key Vault
resource "azurerm_key_vault_secret" "gitlab_root_password" {
  name         = "gitlab-root-password"
  value        = var.gitlab_root_password
  key_vault_id = module.key_vault.id
  content_type = "password"
  depends_on = [time_sleep.wait_for_rbac]
}

resource "azurerm_key_vault_secret" "gitlab_runner_token" {
  name         = "gitlab-runner-token"
  value        = var.gitlab_runner_token
  key_vault_id = module.key_vault.id
  content_type = "token"
  depends_on = [time_sleep.wait_for_rbac]
}

# Grant Container App managed identity access to read secrets
resource "azurerm_role_assignment" "gitlab_app_kv_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.identity.principal_id
}

########## Storage Account + Azure Files Shares ##########
module "storage_account" {
  source                   = "./modules/storage-account"
  name                     = "stgitlab${local.unique_suffix}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_replication_type = var.storage_account_replication_type
  tags                     = local.base_tags
}

# Dynamically create file shares based on tfvars input
module "file_share" {
  for_each = { for share in var.file_shares : share.name => share }

  source               = "./modules/file-share"
  name                 = each.value.name
  storage_account_name = module.storage_account.name
  quota                = each.value.quota
}

########## Private Endpoints ##########
module "private_endpoint_storage_file" {
  source                         = "./modules/private-endpoint"
  name                           = "pe-st-file-${local.unique_suffix}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  subnet_id                      = var.private_endpoints_subnet_id
  private_connection_resource_id = module.storage_account.id
  subresource_names              = ["file"]
  tags                           = local.base_tags
}

module "private_endpoint_acr" {
  source                         = "./modules/private-endpoint"
  name                           = "pe-acr-${local.unique_suffix}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  subnet_id                      = var.private_endpoints_subnet_id
  private_connection_resource_id = module.acr.id
  subresource_names              = ["registry"]
  tags                           = local.base_tags
}

module "private_endpoint_key_vault" {
  source                         = "./modules/private-endpoint"
  name                           = "pe-kv-${local.unique_suffix}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  subnet_id                      = var.private_endpoints_subnet_id
  private_connection_resource_id = module.key_vault.id
  subresource_names              = ["vault"]
  tags                           = local.base_tags
}

########## Container App Environment ##########
module "container_app_environment" {
  source                     = "./modules/container-app-environment"
  name                       = "cae-gitlab-${local.unique_suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = module.log_analytics.id
  infrastructure_subnet_id   = var.container_apps_subnet_id
  workload_profile_type      = var.workload_profile_type
  workload_profile_name      = var.workload_profile_name
  tags                       = local.base_tags
}

########## GitLab Container App ##########
module "gitlab_app" {
  source                       = "./modules/container-app"
  name                         = "ca-gitlab-${local.unique_suffix}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  environment_id               = module.container_app_environment.id
  image                        = "gitlab/gitlab-ee:latest"
  cpu                          = 2.0
  memory                       = "4Gi"
  min_replicas                 = 1
  max_replicas                 = 1
  target_port                  = 80
  external_enabled             = true
  registry_server              = module.acr.login_server
  registry_identity_id         = module.identity.id
  identity_ids                 = [module.identity.id]
  gitlab_hostname              = var.gitlab_hostname
  key_vault_secret_id_password = azurerm_key_vault_secret.gitlab_root_password.id
  key_vault_secret_id_token    = azurerm_key_vault_secret.gitlab_runner_token.id
  storage_account_name         = module.storage_account.name
  storage_account_key          = module.storage_account.primary_access_key
  file_shares = [
    for share in var.file_shares : {
      name = share.name
      path = share.path
    }
  ]
  tags = local.base_tags

  depends_on = [
    module.file_share,
    module.private_endpoint_storage_file,
    module.private_endpoint_acr,
    azurerm_role_assignment.gitlab_app_kv_secrets_user
  ]
}

# GitLab on Azure Container Apps - GitHub Copilot Instructions

## Project Overview

This repository contains an Azure Container Apps deployment of GitLab Enterprise Edition (`gitlab/gitlab-ee` Docker image) provisioned entirely with Terraform. The Azure Developer CLI (`azd`) template is intentionally minimal (no hooks) and does not orchestrate Terraform. All lifecycle operations (create/update/destroy) are performed with Terraform commands.

### Architecture Goals

- **GitLab Container App**: Single container app running the official `gitlab/gitlab-ee` image
- **Azure Files NFS Mount**: Persistent storage for GitLab data (repositories, database, etc.)
- **Private Networking**: Deployed in a VNet with private endpoints for all services
- **IaC with Terraform**: All infrastructure provisioned via modular Terraform
- **Azure Developer CLI**: Minimal template only (no deployment hooks)

## Infrastructure Components

### Required Azure Resources

1. **Networking**:

- Existing VNet (resource ID provided via tfvars)
- Existing Container Apps subnet (resource ID provided via tfvars)
- Existing Private Endpoints subnet (resource ID provided via tfvars)
- Network Security Groups (NSGs) associated to those existing subnets
- (Do NOT manually create Private DNS zones; they are auto-managed via Azure Policy (DINE))

2. **Container Apps**:

   - Container Apps Environment (VNet-integrated)
   - Container App running `gitlab/gitlab-ee:latest`
   - User-assigned managed identity for authentication

3. **Storage**:

   - Azure Storage Account (with NFS 3.0 enabled)
   - Azure Files Premium share for GitLab data
   - Private endpoint for storage account

4. **Supporting Services**:
   - Azure Container Registry (ACR) with private endpoint
   - Log Analytics Workspace
   - Application Insights
   - Azure Key Vault (for secrets management) with private endpoint

### Network & Input Requirements (User-Specified in tfvars)

Users must provide (via `terraform.tfvars` or environment variables):

- Existing Resource Group name
- Existing Container Apps subnet resource ID (pre-created)
- Existing Private Endpoints subnet resource ID (pre-created)
- Location / region
- GitLab hostname (for `external_url`)
- Storage replication type (`LRS` or `ZRS`)
- File shares array: each with `name`, `quota` (GiB), and `path` (container mount point)
- Initial secret values (root password, runner registration token) which are ingested into Key Vault

Note: No `vnet_id` variable (removed—subnet IDs imply VNet).

## Terraform Structure

Follow the modular pattern (key modules shown):

```
infra/
├── main.tf                    # Root configuration
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── versions.tf                # Provider versions
├── terraform.tfvars.example   # Example configuration
└── modules/
    ├── foundation/            # Unique suffix generation
    ├── network/               # NSG and subnet configuration
    ├── storage-account/       # Storage with NFS
    ├── file-share/            # Azure Files share
    ├── private-endpoint/      # Generic private endpoint
    ├── container-app-environment/  # VNet-integrated CAE
    ├── container-app/         # GitLab container app
    ├── acr/                   # Container registry
    ├── identity/              # Managed identity
    ├── log-analytics/         # Log workspace
    ├── app-insights/          # Application monitoring
    └── key-vault/             # Secrets management
```

### Key Terraform Patterns

1. **Provider & Backend**:

   ```hcl
   terraform {
     required_providers {
       azurerm = { source = "hashicorp/azurerm", version = "~> 4.37" }
       azapi   = { source = "azure/azapi", version = "~> 2.5" }
       random  = { source = "hashicorp/random", version = "~> 3.7" }
     }
     required_version = ">= 1.10.0, < 2.0.0"
     backend "azurerm" {}
   }
   ```

2. **Module Pattern (Secret IDs passed instead of raw values)**:

   ```hcl
   module "gitlab_app" {
     source                       = "./modules/container-app"
     name                         = "ca-gitlab-${local.unique_suffix}"
     environment_id               = module.container_app_environment.id
     resource_group_name          = var.resource_group_name
     image                        = "gitlab/gitlab-ee:latest"
     cpu                          = 2.0
     memory                       = "4Gi"
     min_replicas                 = 1
     max_replicas                 = 1
     external_enabled             = true
     target_port                  = 80
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
     tags                         = local.base_tags
   }
   ```

3. **File Shares Dynamic Creation**:

   ```hcl
   module "file_share" {
     for_each = { for share in var.file_shares : share.name => share }

     source               = "./modules/file-share"
     name                 = each.value.name
     storage_account_name = module.storage_account.name
     quota                = each.value.quota
   }
   ```

4. **VNet Integration**:

   ```hcl
   resource "azurerm_container_app_environment" "main" {
     name                       = var.name
     location                   = var.location
     resource_group_name        = var.resource_group_name
     log_analytics_workspace_id = var.log_analytics_workspace_id
     infrastructure_subnet_id   = var.infrastructure_subnet_id
     internal_load_balancer_enabled = true
     tags                       = var.tags
   }
   ```

5. **Azure Files NFS Mount (Dynamic Volume Pattern)**:

   ```hcl
   resource "azurerm_container_app" "main" {
     # ... other config ...

     template {
       container {
         # ... container config ...

         dynamic "volume_mounts" {
           for_each = var.file_shares
           content {
             name = volume_mounts.value.name
             path = volume_mounts.value.path
           }
         }
       }

       dynamic "volume" {
         for_each = var.file_shares
         content {
           name         = volume.value.name
           storage_type = "AzureFile"
           storage_name = volume.value.name
         }
       }
     }
   }

   # Environment storage mounts with access key
   resource "azurerm_container_app_environment_storage" "shares" {
     for_each = { for share in var.file_shares : share.name => share }

     name                         = each.value.name
     container_app_environment_id = var.environment_id
     account_name                 = var.storage_account_name
     share_name                   = each.value.name
     access_mode                  = "ReadWrite"
     access_key                   = var.storage_account_key
   }
   ```

## GitLab Configuration

### Docker Image

Use the official GitLab Enterprise Edition image:

```
gitlab/gitlab-ee:latest
```

### GitLab Configuration Files

Reference the official GitLab Docker assets:

- Base configuration wrapper script
- Assets located at: https://gitlab.com/gitlab-org/omnibus-gitlab/-/tree/master/docker/assets

### Container App Configuration & Secrets

Secrets are never injected via plain `env` values. They are stored in Key Vault and referenced with `secret_name`.

Snippet from `modules/container-app/main.tf`:

```hcl
env {
  name  = "GITLAB_OMNIBUS_CONFIG"
  value = <<-EOT
    external_url 'https://${var.gitlab_hostname}'
    gitlab_rails['gitlab_shell_ssh_port'] = 2222
    gitlab_rails['shared_path'] = '/var/opt/gitlab/gitlab-rails/shared'
    git_data_dirs({ "default" => { "path" => "/var/opt/gitlab/git-data" } })
    prometheus_monitoring['enable'] = false
    puma['worker_processes'] = 2
    sidekiq['max_concurrency'] = 10
  EOT
}
env { name = "GITLAB_ROOT_PASSWORD"                  secret_name = "gitlab-root-password" }
env { name = "GITLAB_SHARED_RUNNERS_REGISTRATION_TOKEN" secret_name = "gitlab-runner-token" }
secret { name = "gitlab-root-password"  key_vault_secret_id = var.key_vault_secret_id_password identity = var.identity_ids[0] }
secret { name = "gitlab-runner-token"  key_vault_secret_id = var.key_vault_secret_id_token   identity = var.identity_ids[0] }
```

### Storage Volume Mounts

GitLab requires three primary mount points:

1. `/etc/gitlab` - Configuration files
2. `/var/opt/gitlab` - Application data, repositories, uploads
3. `/var/log/gitlab` - Logs

## Azure Developer CLI (azd) Template

Current minimal `azure.yaml`:

```yaml
name: gitlab-on-aca
metadata:
  template: gitlab-on-aca@0.0.1-alpha
services: {}
```

Terraform directly provisions all resources; azd may be leveraged later for additional services.

## Terraform Remote State & Workflow

1. Create (or reference) storage account & blob container for state.
2. Initialize backend:
   ```bash
   terraform init \
     -backend-config="resource_group_name=<rg>" \
     -backend-config="storage_account_name=<stateacct>" \
     -backend-config="container_name=<container>" \
     -backend-config="key=gitlab-on-aca.tfstate"
   ```
3. Validate & plan:
   ```bash
   terraform validate
   terraform plan -var-file=terraform.tfvars
   ```
4. Apply:
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```
5. Destroy:
   ```bash
   terraform destroy -var-file=terraform.tfvars
   ```

## Networking and Security

### Network Security Groups

**Container Apps Subnet NSG**:

```hcl
# Allow Container Apps control plane
rule {
  name                       = "AllowCAEControlPlane"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "443"
  source_address_prefix      = "AzureCloud"
  destination_address_prefix = "*"
}

# Allow internal communication
rule {
  name                       = "AllowInternalComms"
  priority                   = 110
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = var.container_apps_subnet_cidr
  destination_address_prefix = var.container_apps_subnet_cidr
}
```

**Private Endpoints Subnet NSG**:

```hcl
# Allow private endpoint traffic
rule {
  name                       = "AllowPrivateEndpoint"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "443"
  source_address_prefix      = "VirtualNetwork"
  destination_address_prefix = "*"
}
```

### Private Endpoints

Required for:

- Azure Storage Account (blob, file, table, queue)
- Azure Container Registry
- Azure Key Vault

Do NOT manually create Private DNS zones, DNS zone groups, or DNS records. An Azure Policy (DINE) deployment automatically creates and links required zone groups and records when private endpoints are provisioned. Ensure only:

1. Correct private endpoint subnet is used
2. Appropriate `subresource_names` are specified (e.g. ["file"], ["blob"], ["vault"], ["registry"])
3. Post-deployment DNS resolution validates expected private IP

```hcl
module "storage_private_endpoint" {
  source              = "./modules/private-endpoint"
  name                = "pe-st-${local.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_connection_resource_id = module.storage_account.id
  subresource_names              = ["file"]

  # Do NOT pass private_dns_zone_ids; DNS handled by DINE Policy
  tags = local.base_tags
}
```

## Resource Sizing Recommendations

### GitLab Container App

**Minimum (Development)**:

- CPU: 2.0 cores
- Memory: 4Gi
- Replicas: 1

**Production**:

- CPU: 4.0 cores
- Memory: 8Gi
- Replicas: 2-3 (for HA)

### Azure Files Storage

- Tier: Premium (hard-coded; required for FileStorage + NFS)
- Replication: Configurable (e.g. LRS/ZRS) via variable; tier is not configurable
- Protocol: NFS 3.0 (enforced `nfsv3_enabled = true`)
- Secure transfer disabled (`https_traffic_only_enabled = false`) for NFS compatibility
- Minimum Share Size: 100 GiB
- Recommended: 500 GiB+ for production

Storage account module pattern (implemented):

```hcl
resource "azurerm_storage_account" "main" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  account_tier               = "Premium"            # Hard-coded: required for NFS FileStorage
  account_replication_type   = var.account_replication_type
  account_kind               = "FileStorage"
  nfsv3_enabled              = true
  https_traffic_only_enabled = false                # Must be disabled for NFS
  tags                       = var.tags
}
```

ACR module pattern (implemented):

```hcl
resource "azurerm_container_registry" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium" # Hard-coded: private endpoint & advanced networking required
  admin_enabled       = false
  tags                = var.tags
}
```

### Container Apps Environment

- Subnet: /23 minimum (512 IPs)
- Dedicated workload profile REQUIRED for VNet integration & NFS performance (Consumption insufficient)

  ```hcl
  resource "azurerm_container_app_environment" "main" {
    name                       = var.name
    location                   = var.location
    resource_group_name        = var.resource_group_name
    log_analytics_workspace_id = var.log_analytics_workspace_id
    infrastructure_subnet_id   = var.infrastructure_subnet_id
    internal_load_balancer_enabled = true

    workload_profile {
      name      = "gitlab-dedicated"
      type      = "Dedicated"
      min_count = 1
      max_count = 3
    }
    tags = var.tags
  }
  ```

## Variable Naming Conventions

Follow Azure naming conventions with prefixes:

- `rg-` - Resource groups
- `vnet-` - Virtual networks
- `snet-` - Subnets
- `nsg-` - Network security groups
- `ca-` - Container apps
- `cae-` - Container app environments
- `st` - Storage accounts (no hyphens)
- `acr` - Container registries (no hyphens)
- `kv-` - Key vaults
- `pe-` - Private endpoints
- `law-` - Log Analytics workspaces
- `appi-` - Application Insights
- `uami-` - User-assigned managed identities

Use `local.unique_suffix` for globally unique resource names.

## Code Generation Guidelines

### When Generating Terraform Code

1. **Always create modular structure** following the reference repository pattern
2. **Use `versions.tf`** in every module; always look up latest stable provider versions before changes:

- Query Terraform Registry for `azurerm`, `azapi`, `random`, `time`
- Maintain major version; update minor/patch (e.g. `~> 4.37` -> latest `4.x`)

3. **Include comprehensive `variables.tf`** with descriptions and types
4. **Provide `outputs.tf`** for resource IDs, names, and endpoints
5. **Add `tags` variable** to all modules (default = {})
6. **Use `azurerm_container_app`** resource (not deprecated resources)
7. **Enable diagnostics** on all supported resources to Log Analytics

### When Using azd

- Keep `azure.yaml` minimal until a need for azd-managed services arises.
- Avoid duplicating Terraform logic in azd hooks.
- If needed, manually sync important outputs with `azd env set`.

### When Working with Private Endpoints

1. **Do NOT create private DNS zones** (DINE Policy auto-provisions)
2. **Use `azurerm_private_endpoint`** with correct `subresource_names`
3. **Skip manual DNS zone group configuration**
4. **Verify DNS resolution** only (nslookup) post-deployment

## Best Practices

### Security

- Store secrets in Azure Key Vault
- Use managed identities for authentication
- Never commit `.tfvars` files with sensitive data
- Use private endpoints for all PaaS services
- Implement NSGs with least-privilege rules
- Enable Azure Monitor and Application Insights

### Performance

- Use Premium storage for Azure Files NFS
- Configure appropriate CPU/memory for GitLab workload
- Enable autoscaling based on CPU/memory metrics
- Use Azure Front Door or Application Gateway for HTTPS termination (optional)

### Reliability

- Deploy Container Apps with min 2 replicas for HA (production)
- Use availability zones for critical resources
- Implement backup strategy for Azure Files
- Configure health probes for container apps
- Set up alerts for critical metrics
- Monitor dedicated workload profile capacity and adjust `max_count`

### Cost Optimization

- Use Consumption workload profile for dev/test (separate environment if NFS not needed)
- Scale down to 1 replica in non-production
- ACR Premium is hard-coded for private endpoints; downgrade only if removing private endpoints (requires code change)
- Right-size storage replication (LRS vs ZRS) and share quota
- Clean up unused resources with `azd down`

## Testing and Validation

### Post-Deployment Checks

```bash
# Verify Container App is running
az containerapp show \
  --name ca-gitlab-${SUFFIX} \
  --resource-group ${RG_NAME}

# Check logs
az containerapp logs show \
  --name ca-gitlab-${SUFFIX} \
  --resource-group ${RG_NAME} \
  --follow

# Test GitLab URL
curl -I https://gitlab.yourdomain.com

# Verify private endpoint DNS resolution
nslookup storageaccount.file.core.windows.net  # Expect private IP from auto-managed DINE DNS
```

### Common Issues

1. **Container App not starting**: Check volume mount configuration
2. **Storage mount failing**: Verify NFS 3.0 is enabled on storage account
3. **Private endpoint DNS not resolving**: Check DNS zone links to VNet
4. **GitLab initialization slow**: Normal on first start (can take 5-10 min)

## Documentation Structure

Maintain these documentation files:

- `README.md` - Project overview and quick start
- `infra/README.md` - Infrastructure details
- `DEPLOYMENT.md` - Step-by-step deployment guide
- `.github/copilot-instructions.md` - This file

## References

- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [GitLab Docker Installation](https://docs.gitlab.com/ee/install/docker.html)
- [Azure Files NFS](https://learn.microsoft.com/azure/storage/files/storage-files-how-to-create-nfs-shares)
- [Azure Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [GitLab Omnibus Assets](https://gitlab.com/gitlab-org/omnibus-gitlab/-/tree/master/docker/assets)

## AI Agent Context

When assisting:

1. Terraform is authoritative; do not introduce parallel provisioning.
2. Maintain existing module boundaries; each new module includes `versions.tf`, `variables.tf`, `outputs.tf`.
3. All networking is private; no public ingress changes unless explicitly requested.
4. Persistence strictly via Azure Files (Premium NFS).
5. Image must remain `gitlab/gitlab-ee` (version pin only if requested).
6. Primary workflow is Terraform; azd file is metadata only.
7. Inputs exclude `vnet_id`; rely on subnet IDs. Secrets flow: user input -> Key Vault secret -> Container App secret reference.
8. File shares defined via `file_shares` array in tfvars; dynamically created and mounted.

### Current Implementation Conventions (Do NOT change without architectural review)

- Feature-required SKUs hard-coded (Storage: Premium FileStorage; ACR: Premium); do not add SKU variables.
- Storage account forces NFS + disables secure transfer.
- Only replication type configurable for storage.
- ACR admin disabled; managed identity handles pulls.
- Subnets referenced by resource ID (no CIDR management in modules).
- NSGs must allow required ports (2049 NFS, 445 SMB if applicable) and control plane.
- Do NOT manage Private DNS zones manually; rely on DINE policy.
- Do not reintroduce removed toggle variables for mandated features.
- Secrets always via Key Vault secret references (`secret_name`).
- Logging (Log Analytics + App Insights) is mandatory; no `create` toggle.
- Storage access uses account keys (Container Apps does not support identity-based Azure Files mounting).

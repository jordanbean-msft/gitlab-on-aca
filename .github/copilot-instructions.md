# GitLab on Azure Container Apps

This repository deploys GitLab Enterprise Edition on Azure Container Apps using Terraform for infrastructure as code. All infrastructure lifecycle operations are managed through Azure Developer CLI (`azd`).

## Quick Start

**CRITICAL: All Terraform operations MUST be performed through Azure Developer CLI (azd).**

```bash
# Provision infrastructure
azd provision

# Full deployment
azd up

# Destroy infrastructure
azd down
```

**DO NOT run terraform commands directly** (init, plan, apply, destroy). The azd template manages Terraform lifecycle, backend configuration, and state management automatically.

## Architecture

- **GitLab Container App**: Single replica running `gitlab/gitlab-ee` image from private Azure Container Registry
- **Azure Files NFS**: Premium tier persistent storage for GitLab data
- **Private Networking**: All services deployed with private endpoints; no public access
- **Infrastructure as Code**: Modular Terraform structure in `infra/` directory

## Project Structure

```
Root/
  azure.yaml                    # Azure Developer CLI template
  AGENTS.md                     # AI agent context
  .github/
    copilot-instructions.md     # This file (repository-wide instructions)
    instructions/               # Path-specific instructions
      terraform.instructions.md # Terraform-specific guidance
      gitlab.instructions.md    # GitLab container app guidance
  infra/                        # Terraform root
    terraform.tfvars            # User configuration
    main.tf, variables.tf, outputs.tf, versions.tf
    modules/                    # Modular infrastructure
```

## Key Conventions

### Workflow
- Primary workflow: Terraform via `azd` commands only
- Never run raw terraform commands
- azd template is minimal (metadata only, no hooks)

### Networking
- All resources use private endpoints
- `public_network_access_enabled = false` for all PaaS services
- Azure Policy (DINE) auto-provisions Private DNS zones
- NSGs allow: 443, 2049 (NFS), 445 (SMB)

### Security
- Secrets stored in Key Vault with RBAC authorization
- Managed identities for authentication
- Never commit `.tfvars` files with sensitive data
- 60s RBAC propagation delay handled via `time_sleep`

### Naming
- Use Azure naming prefixes: `rg-`, `vnet-`, `snet-`, `nsg-`, `ca-`, `cae-`, `st`, `acr`, `kv-`, `pe-`, `law-`, `appi-`, `uami-`
- Use `local.unique_suffix` for globally unique names

## Common Issues

1. **Container App not starting**: Check volume mount configuration
2. **Storage mount failing**: Verify private endpoint deployment
3. **Private endpoint DNS issues**: DINE policy should auto-create DNS zone groups
4. **GitLab initialization slow**: Normal (10-15 min first start)
5. **Key Vault access denied**: Verify RBAC propagation (60s delay)
6. **ActivationFailed with 301/302**: Wrong probe path or HTTPS redirect enabled
7. **External 503**: Internal services still converging

## Testing

```bash
# Verify deployment
az containerapp show --name ca-gitlab-${SUFFIX} --resource-group ${RG_NAME}

# Check logs (max 300 lines via CLI)
az containerapp logs show --name ca-gitlab-${SUFFIX} --resource-group ${RG_NAME} --tail 300

# For more than 300 log lines, use Log Analytics query
az monitor log-analytics query \
  --workspace ${LOG_ANALYTICS_WORKSPACE_ID} \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'ca-gitlab-${SUFFIX}' | order by TimeGenerated desc | take 1000"

# Verify DNS resolution (should return private IP)
nslookup storageaccount.file.core.windows.net
```

## References

- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [GitLab Docker](https://docs.gitlab.com/ee/install/docker.html)
- [Azure Files NFS](https://learn.microsoft.com/azure/storage/files/storage-files-how-to-create-nfs-shares)
- [Azure Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)

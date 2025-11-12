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

   - Azure Storage Account (Premium FileStorage with public access disabled)
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
- Workload profile type (e.g. `D4`, `D8`, `D16`, `D32`, `E4`, `E8`, `E16`, `E32`, or `Consumption`)
- Workload profile name (must be <16 characters)
- Azure Principal ID (object ID of identity running azd/terraform for Key Vault RBAC)
- File shares array: each with `name`, `quota` (GiB), and `path` (container mount point)
- Initial secret values (root password, runner registration token) which are ingested into Key Vault

## Terraform Structure

Follow modular pattern with standard module structure:

- Each module includes: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Root configuration in `infra/`: main, variables, outputs, versions, tfvars
- Modules in `infra/modules/`: foundation, network, storage-account, file-share, private-endpoint, container-app-environment, container-app, acr, identity, log-analytics, app-insights, key-vault

### Key Terraform Patterns

1. **Providers**: Use azurerm (~> 4.37), azapi (~> 2.5), random (~> 3.7), time (~> 0.13) with Terraform >= 1.10.0
2. **Module Inputs**: Pass Key Vault secret IDs (not raw values); use managed identity IDs for authentication
3. **Dynamic Resources**: Use `for_each` for file shares, environment storage, and volumes
4. **Dependencies**: Explicit `depends_on` for RBAC propagation (time_sleep) and environment storage before container app

## GitLab Configuration

- **Image**: `gitlab/gitlab-ee:latest` (official GitLab Enterprise Edition)
- **Configuration**: GitLab Omnibus config via environment variable; reference [GitLab Docker assets](https://gitlab.com/gitlab-org/omnibus-gitlab/-/tree/master/docker/assets)
- **Secrets**: Stored in Key Vault, referenced in container app via `secret_name` (never plain env values)
- **Storage Mounts**: Three primary paths: `/etc/gitlab` (config), `/var/opt/gitlab` (data/repos), `/var/log/gitlab` (logs)
- **Container Port / Probes**: GitLab listens on internal port **8080** (not 80). `target_port` and all health probes must point to 8080. Ingress exposes HTTPS externally while probes remain HTTP against 8080.
- **Health Probes** (bootstrap mode):
  - Startup probe path: `/-/health` (GitLab does NOT provide `/-/startup`; using it causes 302 redirects and activation failure)
  - Readiness probe path: `/-/readiness`
  - Liveness probe path: `/-/liveness`
  - Bootstrap thresholds intentionally high (e.g. failure thresholds 30) to allow 10–15 min first‑run initialization.
- **HTTPS Redirect**: `nginx['redirect_http_to_https'] = false` must remain disabled so Azure Container Apps HTTP health probes receive 200 responses (probes only use HTTP). Re‑enable only if/when Azure supports HTTPS probe endpoints or a sidecar handles probe translation.
- **Let's Encrypt**: Disabled inside the container: `letsencrypt['enable']=false` and `letsencrypt['auto_renew']=false`. For platform domains use the managed certificate automatically provided, or for custom domains bind a managed/bring‑your‑own cert at the Container App layer (not Omnibus ACME) to avoid ACME HTTP-01 validation failures through the platform ingress.
- **Omnibus Config Snippet (current essentials)**:
  ```ruby
  external_url 'https://${gitlab_hostname}'
  letsencrypt['enable'] = false
  letsencrypt['auto_renew'] = false
  nginx['redirect_http_to_https'] = false  # Required for ACA HTTP probes
  gitlab_rails['gitlab_shell_ssh_port'] = 2222
  # (Storage mounts, external DB, Puma/Sidekiq tuning defined in template)
  ```
  Do not add custom nginx server blocks for redirects unless probes are accounted for.

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

**CRITICAL: All Terraform operations MUST be performed through Azure Developer CLI (azd).**

1. Provision infrastructure:
   ```bash
   azd provision
   ```
2. Full deployment (provision + deploy):
   ```bash
   azd up
   ```
3. Destroy infrastructure:
   ```bash
   azd down
   ```

**DO NOT run terraform commands directly** (init, plan, apply, destroy). The azd template manages Terraform lifecycle, backend configuration, and state management automatically.

## Networking and Security

### Network Security Group Rules

- **Container Apps Subnet**: Allow control plane (443), internal VNet traffic, outbound NFS/SMB (2049, 445)
- **Private Endpoints Subnet**: Allow inbound HTTPS (443) and file share protocols (2049, 445) from VNet

### Private Endpoint Requirements

1. All PaaS services (Storage, ACR, Key Vault) use private endpoints with `public_network_access_enabled = false`
2. Correct `subresource_names` required (e.g. ["file"], ["registry"], ["vault"])
3. **Do NOT create private DNS zones manually** - Azure Policy (DINE) auto-provisions zones and records
4. Private endpoints must `ignore_changes = [private_dns_zone_group]` in lifecycle
5. Verify DNS resolution post-deployment (nslookup should return private IPs)

## Resource Sizing Recommendations

### GitLab Container App

- CPU: 4.0 cores, Memory: 8Gi, Replicas: 1 (only a single replica supported for GitLab EE in this design)

### Azure Files Storage

- Tier: Premium (hard-coded; required for FileStorage + NFS)
- Replication: Configurable (LRS/ZRS) via variable
- Protocol: NFS 3.0 (implicit for FileStorage Premium)
- Minimum Share Size: 100 GiB
- Recommended: 500 GiB+ for production
- Secure transfer disabled (`https_traffic_only_enabled = false`) for NFS compatibility
- Public access disabled (`public_network_access_enabled = false`)

### Container Apps Environment

- Subnet: /27 minimum (512 IPs)
- Dedicated workload profile REQUIRED for VNet integration & NFS performance
- Workload profile name must be <16 characters
- Workload profile type: D4, D8, D16, D32, E4, E8, E16, E32, or Consumption
- **CRITICAL**: Container app resource MUST set `workload_profile_name` to bind to dedicated profile (defaults to Consumption if omitted)

### Key Vault, ACR, Storage Account Configuration

- All services: `public_network_access_enabled = false` with private endpoints
- Key Vault: RBAC authorization (`rbac_authorization_enabled = true`), 60s RBAC propagation delay
- ACR: Premium SKU (hard-coded for private endpoint support), admin disabled
- Storage: Premium FileStorage (hard-coded), only replication type configurable

## Variable Naming Conventions

Follow Azure naming conventions with prefixes:

- `rg-` Resource groups, `vnet-` Virtual networks, `snet-` Subnets, `nsg-` Network security groups
- `ca-` Container apps, `cae-` Container app environments
- `st` Storage accounts (no hyphens), `acr` Container registries (no hyphens)
- `kv-` Key vaults, `pe-` Private endpoints
- `law-` Log Analytics workspaces, `appi-` Application Insights, `uami-` User-assigned managed identities

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
7. **ALWAYS enable diagnostic settings (`azurerm_monitor_diagnostic_setting`)** on all supported Azure resources, sending logs and metrics to Log Analytics workspace
   - Include all available log categories and AllMetrics
   - Pass `log_analytics_workspace_id` as a module variable
   - Name diagnostic setting as `diag-{resource-name}`

### When Using azd

- Keep `azure.yaml` minimal until a need for azd-managed services arises
- Avoid duplicating Terraform logic in azd hooks
- If needed, manually sync important outputs with `azd env set`

### When Working with Private Endpoints

1. **Do NOT create private DNS zones** (Deploy-If-Not-Exists (DINE) Policy auto-provisions DNS records via zone groups, no manual management needed)
2. **Use `azurerm_private_endpoint`** with correct `subresource_names`
3. **Skip manual DNS zone group configuration**
4. **Verify DNS resolution** only (nslookup) post-deployment

### When Configuring NFS Storage

1. **Storage account**: FileStorage Premium, `https_traffic_only_enabled = false`, `public_network_access_enabled = false`
2. **File shares**: Set `enabled_protocol = "NFS"` on azurerm_storage_share
3. **Environment storage**: Use `nfs_server_url` parameter, omit `access_key` for NFS
4. **Container app volumes**: Use `storage_type = "NfsAzureFile"`
5. **NSG rules**: Allow ports 2049 (NFS) and 445 (SMB) inbound on private endpoints subnet

## Best Practices

### Security

- Store secrets in Azure Key Vault
- Use managed identities for authentication
- Never commit `.tfvars` files with sensitive data
- Use private endpoints for all PaaS services
- Implement NSGs with least-privilege rules
- Enable Azure Monitor and Application Insights
- **Always configure diagnostic settings for all Azure services** - send logs and metrics to Log Analytics workspace

### Performance

- Use Premium storage for Azure Files NFS
- Configure appropriate CPU/memory for GitLab workload
- Enable autoscaling based on CPU/memory metrics

### Reliability

- Deploy Container Apps with min 2 replicas for HA (production)
- Use availability zones for critical resources
- Implement backup strategy for Azure Files
- Configure health probes for container apps
- Set up alerts for critical metrics
- Monitor dedicated workload profile capacity and adjust `max_count`

### Cost Optimization

- Scale down to 1 replica in non-production
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
2. **Storage mount failing**: Verify storage account has public access disabled and private endpoint is deployed
3. **Private endpoint DNS not resolving**: Verify DINE policy created DNS zone groups automatically (check `private_dns_zone_group` in portal)
4. **GitLab initialization slow**: Normal on first start (can take 10–15 min; background migrations, asset compilation)
5. **Key Vault access denied**: Ensure `azure_principal_id` is set in azd environment and RBAC role assignments have propagated (60s wait configured)
6. **ActivationFailed with 301/302 or 502 probe logs**: Usually caused by wrong probe path (`/-/startup`), HTTPS redirect enabled, or probes hitting port 80 instead of 8080.
7. **Persistent 503 externally but probes pass**: Application may still be converging internal services (Sidekiq, migrations). Confirm readiness with internal `curl http://localhost:8080/-/readiness` via `az containerapp exec`.

### Probe Troubleshooting Quick Reference

| Symptom                                       | Likely Cause                             | Fix                                               |
| --------------------------------------------- | ---------------------------------------- | ------------------------------------------------- |
| Startup probe 301/302 to `/users/sign_in`     | Using `/-/startup` path                  | Change to `/-/health`                             |
| Readiness 502                                 | App not yet ready or wrong port (80)     | Ensure port 8080 + wait for initialization        |
| All probes fail after enabling HTTPS redirect | `nginx['redirect_http_to_https'] = true` | Set `nginx['redirect_http_to_https'] = false`     |
| ACME/Let’s Encrypt errors in logs             | Built‑in LE enabled on platform domain   | Keep LE disabled; use platform/custom domain cert |
| External 503 while probes OK                  | Internal services still warming up       | Allow bootstrap window; check Sidekiq/Puma logs   |

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
9. All PaaS services (Storage, ACR, Key Vault) have `public_network_access_enabled = false` and use private endpoints.
10. Key Vault uses RBAC authorization (`rbac_authorization_enabled = true`), not vault access policies.
11. RBAC propagation delay handled via `time_sleep` resource (60s) before creating Key Vault secrets.
12. Private endpoints ignore DNS zone group lifecycle changes (managed by Azure Policy DINE).

### Current Implementation Conventions (Do NOT change without architectural review)

- **Hard-coded SKUs**: Storage (Premium FileStorage), ACR (Premium) - required for features; no SKU variables
- **Storage NFS**: Implicit for FileStorage Premium; secure transfer disabled for NFS
- **Replication**: Only storage replication type configurable
- **ACR**: Admin disabled; managed identity handles pulls
- **Subnets**: Referenced by resource ID (no CIDR management in modules)
- **NSGs**: Must allow ports 2049 (NFS), 445 (SMB), 443 (control plane)
- **DNS**: Do NOT manage Private DNS zones manually; rely on DINE policy
- **Secrets**: Always via Key Vault secret references (`secret_name`), never plain env
- **Logging**: Log Analytics + App Insights mandatory; no toggle
- **Storage Access**: Account keys for Container Apps (identity-based mounting not supported)
- **Workload Profile**: Name <16 chars; type must be valid SKU (D4/D8/D16/D32/E4/E8/E16/E32/Consumption); **container app must explicitly set `workload_profile_name` in resource block**
- **RBAC**: `AZURE_PRINCIPAL_ID` always provided via azd environment for Key Vault Administrator role
- **NFS Storage**: Use `nfs_server_url`, set `enabled_protocol = "NFS"` on shares, omit `access_key`
- **Container Port & Probes**: `target_port = 8080`; probes (`/-/health`, `/-/readiness`, `/-/liveness`) must reference 8080. Do NOT revert to 80.
- **HTTPS Redirect Disabled for Probes**: Keep `nginx['redirect_http_to_https']=false` until probe protocol flexibility is available.
- **ACME Disabled**: Rely on Container Apps managed or custom certs; do not re‑enable Omnibus Let’s Encrypt without redesigning probe & ingress strategy.

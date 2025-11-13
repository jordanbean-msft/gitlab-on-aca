# AI Agent Context for GitLab on Azure Container Apps

## Repository Overview

This is an Azure Container Apps deployment of GitLab Enterprise Edition (`gitlab/gitlab-ee`) provisioned entirely with Terraform. The repository follows Infrastructure as Code (IaC) principles with a modular Terraform structure.

## Critical Workflow Rules

1. **Terraform is authoritative** - Do not introduce parallel provisioning methods
2. **ALL Terraform operations via azd** - Never run terraform commands directly (init, plan, apply, destroy)
3. **Maintain module boundaries** - Each module includes: `versions.tf`, `variables.tf`, `outputs.tf`, `main.tf`
4. **Private networking only** - No public ingress changes unless explicitly requested
5. **Persistence via Azure Files** - Premium NFS only
6. **Image deployment** - Always from private ACR copy (`<acr_login_server>/gitlab/gitlab-ee:<tag>`), imported via Terraform ARM `importImage` action with `Force` mode

## Input Configuration

- **Subnets**: Provided as resource IDs (no VNet ID or CIDR management)
- **Secrets**: Flow from user input → Key Vault secret → Container App secret reference
- **File Shares**: Defined via `file_shares` array in tfvars; dynamically created and mounted
- **RBAC**: `AZURE_PRINCIPAL_ID` always provided via azd environment for Key Vault Administrator role

## Hard-Coded Implementation Details (Do NOT change without architectural review)

### SKUs and Tiers

- Storage: Premium FileStorage (required for NFS features)
- ACR: Premium (required for private endpoints)
- No SKU variables - these are infrastructure requirements

### Storage Configuration

- NFS: Implicit for FileStorage Premium
- Secure transfer: Disabled for NFS compatibility (`https_traffic_only_enabled = false`)
- Replication: Only type configurable (LRS/ZRS)
- Public access: Disabled (`public_network_access_enabled = false`)

### Security Patterns

- ACR: Admin disabled; managed identity handles pulls
- Key Vault: RBAC authorization (`rbac_authorization_enabled = true`), NOT vault access policies
- RBAC propagation: 60s delay via `time_sleep` before Key Vault secret creation
- Private endpoints: Ignore DNS zone group lifecycle (`ignore_changes = [private_dns_zone_group]`)

### DNS Management

- **Do NOT manage Private DNS zones manually**
- Azure Policy (Deploy-If-Not-Exists) auto-provisions DNS records via zone groups
- Private endpoints automatically get DNS configuration

### Networking Requirements

NSGs must allow:

- Container Apps Subnet: 2049 (NFS), 445 (SMB), 443 (control plane)
- Private Endpoints Subnet: 2049 (NFS), 445 (SMB), 443 (HTTPS)

### Secrets Management

- Always via Key Vault secret references (`secret_name`)
- Never plain environment variables
- Container app retrieves at runtime using managed identity

### Monitoring

- Log Analytics + App Insights: Mandatory
- Diagnostic settings: Required for ALL Azure resources
- Send all log categories and AllMetrics to Log Analytics

### Storage Access

- Account keys for Container Apps (identity-based mounting not supported for NFS)
- Use `nfs_server_url` in environment storage
- Set `enabled_protocol = "NFS"` on shares
- Omit `access_key` for NFS mounts

### Workload Profile

- Name: <16 characters required
- Type: Must be valid SKU (D4/D8/D16/D32/E4/E8/E16/E32/Consumption)
- **Container app MUST explicitly set `workload_profile_name`** in resource block

### Container Port & Probes

- `target_port = 8080` (GitLab internal port)
- Probes: `/-/health`, `/-/readiness`, `/-/liveness` (all port 8080)
- **Do NOT revert to port 80**

### GitLab Omnibus Configuration

- HTTPS redirect: Disabled for probes (`nginx['redirect_http_to_https']=false`)
- ACME: Disabled (rely on Container Apps managed/custom certs)
- Do NOT re-enable Let's Encrypt without redesigning probe & ingress strategy

## Architecture Decisions

### Why these patterns exist:

1. **Premium FileStorage**: Required for NFS 3.0 protocol support
2. **Premium ACR**: Required for private endpoint support
3. **RBAC Key Vault**: Modern Azure security model; more flexible than access policies
4. **DINE DNS**: Automated compliance with private endpoint DNS requirements
5. **Port 8080**: GitLab's default internal HTTP port; 80 not exposed
6. **HTTP Probes**: Azure Container Apps doesn't support HTTPS probe endpoints
7. **Single Replica**: GitLab EE shared storage architecture limitation
8. **Private ACR Import**: Avoid public registry rate limits; ensure private network path

## When Assisting with Changes

### Before making changes:

1. Query Terraform Registry for latest provider versions
2. Review existing module structure and patterns
3. Verify change aligns with private networking architecture
4. Confirm secrets flow through Key Vault
5. Check diagnostic settings inclusion

### Always include:

- All 4 module files (main, variables, outputs, versions)
- Tags variable in modules
- Diagnostic settings for new resources
- Lifecycle ignore for private_dns_zone_group on private endpoints
- Explicit `workload_profile_name` on container app resource

### Never:

- Create Private DNS zones manually
- Use plain environment variables for secrets
- Make SKUs configurable (Storage FileStorage, ACR Premium)
- Run terraform commands directly
- Enable Let's Encrypt in Omnibus config
- Enable HTTPS redirect in nginx config
- Use port 80 for container or probes
- Create duplicate infrastructure in azd hooks

## Testing Strategy

After changes:

1. Validate Terraform: `terraform validate` (via azd provision)
2. Check private endpoint DNS resolution
3. Verify container app activation (may take 10-15 min first run)
4. Test health endpoints: `/-/health`, `/-/readiness`, `/-/liveness`
5. Confirm external URL accessibility
6. Review logs for probe failures or ACME errors

## Documentation References

- Azure Container Apps: https://learn.microsoft.com/azure/container-apps/
- GitLab Docker: https://docs.gitlab.com/ee/install/docker.html
- GitLab Omnibus Assets: https://gitlab.com/gitlab-org/omnibus-gitlab/-/tree/master/docker/assets
- Azure Files NFS: https://learn.microsoft.com/azure/storage/files/storage-files-how-to-create-nfs-shares
- Azure Private Endpoints: https://learn.microsoft.com/azure/private-link/private-endpoint-overview

## Current Implementation Status

- Primary workflow: Terraform via azd
- azd file: Metadata only (no hooks)
- Networking: Private endpoints with DINE DNS
- Storage: Premium NFS Azure Files
- Image: Private ACR with ARM importImage
- Secrets: Key Vault RBAC
- Monitoring: Log Analytics + App Insights
- Probes: HTTP on port 8080 (bootstrap mode with high thresholds)

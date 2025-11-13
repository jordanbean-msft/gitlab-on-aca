---
applyTo: "infra/**/*.tf,infra/**/*.tfvars"
---

# Terraform Infrastructure Instructions

## Module Structure

Each module MUST include:
- `main.tf` - Resource definitions
- `variables.tf` - Input variables with descriptions and types
- `outputs.tf` - Output values for resource IDs, names, endpoints
- `versions.tf` - Provider version constraints

## Provider Versions

Always query Terraform Registry for latest stable versions before making changes:
- `azurerm` ~> 4.37 (maintain major version 4.x)
- `azapi` ~> 2.5 (maintain major version 2.x)
- `random` ~> 3.7 (maintain major version 3.x)
- `time` ~> 0.13 (maintain major version 0.x)
- Terraform >= 1.10.0

## Required Patterns

1. **Dynamic Resources**: Use `for_each` for file shares, environment storage, and volumes
2. **Dependencies**: Explicit `depends_on` for RBAC propagation (time_sleep) and environment storage before container app
3. **Tags**: Every module accepts `tags` variable (type = map(string), default = {})
4. **Diagnostic Settings**: ALWAYS create `azurerm_monitor_diagnostic_setting` for all supported resources
   - Send all log categories and AllMetrics to Log Analytics workspace
   - Pass `log_analytics_workspace_id` as module variable
   - Name: `diag-{resource-name}`

## Hard-Coded SKUs (Do NOT make configurable)

- **Storage Account**: Premium FileStorage (required for NFS)
- **ACR**: Premium (required for private endpoints)
- **Storage Replication**: Only replication type (LRS/ZRS) is configurable

## NFS Storage Configuration

1. **Storage account**:
   - Kind: FileStorage
   - Tier: Premium
   - `https_traffic_only_enabled = false` (NFS requirement)
   - `public_network_access_enabled = false`

2. **File shares**:
   - Set `enabled_protocol = "NFS"` on `azurerm_storage_share`
   - Minimum quota: 100 GiB

3. **Environment storage**:
   - Use `nfs_server_url` parameter
   - Omit `access_key` for NFS

4. **Container app volumes**:
   - Use `storage_type = "NfsAzureFile"`

## Private Endpoint Requirements

1. All PaaS services require private endpoints
2. Correct `subresource_names`:
   - Storage: `["file"]`
   - ACR: `["registry"]`
   - Key Vault: `["vault"]`
3. **Do NOT create private DNS zones** - Azure Policy (DINE) handles this
4. Private endpoints MUST include:
   ```hcl
   lifecycle {
     ignore_changes = [private_dns_zone_group]
   }
   ```

## Key Vault Configuration

- Use RBAC authorization: `rbac_authorization_enabled = true`
- NOT vault access policies
- Include 60s RBAC propagation delay via `time_sleep` resource
- `public_network_access_enabled = false`

## Container App Configuration

- **MUST set `workload_profile_name`** in resource block (defaults to Consumption if omitted)
- Workload profile name <16 characters
- Valid types: D4, D8, D16, D32, E4, E8, E16, E32, Consumption
- Port configuration: `target_port = 8080` (GitLab internal port)
- Health probes: All must reference port 8080
  - Startup: `/-/health` (NOT `/-/startup`)
  - Readiness: `/-/readiness`
  - Liveness: `/-/liveness`

## Secret Management

- All secrets stored in Key Vault
- Container app references via `secret_name` (never plain env values)
- Module inputs: Pass Key Vault secret IDs, not raw values
- Use managed identity IDs for authentication

## NSG Rules Required

Container Apps Subnet:
- Allow 443 (control plane)
- Allow internal VNet traffic
- Allow outbound 2049 (NFS), 445 (SMB)

Private Endpoints Subnet:
- Allow inbound 443
- Allow inbound 2049 (NFS), 445 (SMB) from VNet

## Variable Conventions

- Use `local.unique_suffix` for globally unique resource names
- Networking: Pass subnet resource IDs (not VNet ID or CIDRs)
- Storage: Array of file shares with `name`, `quota`, `path`
- Secrets: Initial values ingested into Key Vault, then referenced

## Code Generation Checklist

Before generating Terraform code:
- [ ] Query Terraform Registry for latest provider versions
- [ ] Include all 4 files: main, variables, outputs, versions
- [ ] Add tags variable to module
- [ ] Configure diagnostic settings for all resources
- [ ] Use correct private endpoint subresource names
- [ ] Set lifecycle ignore for private_dns_zone_group
- [ ] Validate NFS storage configuration
- [ ] Ensure workload_profile_name is set on container app

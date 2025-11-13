# GitLab on Azure Container Apps

This repository provisions a fully private Azure Container Apps deployment running the official `gitlab/gitlab-ee` image. All Azure resources are created **exclusively via Terraform**.

> Deploys GitLab Enterprise Edition on Azure Container Apps with VNet integration, private networking, persistent NFS storage, and supporting Azure services (ACR, Key Vault, monitoring). All PaaS services use private endpoints.

## Architecture

![architecture](./.img/architecture.png)

### Key Design Principles

This deployment follows Infrastructure as Code best practices with these architectural decisions:

1. **Terraform-First**: All infrastructure lifecycle managed through Terraform
2. **Private Networking**: Zero public ingress; all PaaS services use private endpoints
3. **Persistent Storage**: Premium NFS Azure Files for GitLab data volumes
4. **Container Registry**: Private ACR with image import from Docker Hub
5. **Secrets Management**: Azure Key Vault with RBAC authorization
6. **Monitoring**: Log Analytics + Application Insights for observability
7. **Modular Structure**: Reusable Terraform modules in `infra/modules/`

### Critical Workflow Rules

- ✅ **All infrastructure via Terraform** - Do not introduce parallel provisioning tools
- ✅ **Use `azd` OR direct Terraform** - Both workflows supported; `azd` simplifies env management
- ✅ **Never run raw `terraform` commands with `azd`** - azd manages Terraform lifecycle
- ✅ **Private networking only** - No public access to storage, ACR, Key Vault, or database
- ✅ **Premium storage tiers** - FileStorage Premium (NFS), ACR Premium (private endpoints)
- ✅ **Secrets via Key Vault** - Never plain environment variables for sensitive data

## Disclaimer

**THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.**

## Prerequisites

You must have the following before provisioning:

- Azure subscription with Owner or Contributor + User Access Administrator roles
- **Existing Resource Group** (referenced in tfvars; Terraform will not create it)
- **Existing Azure Storage Account + Blob Container** for Terraform remote state (configure during `terraform init`)
- Existing VNet with:
  - Container Apps subnet (/27 minimum, delegated to `Microsoft.App/environments`)
  - Private Endpoints subnet (/27+ recommended)
- Azure Policy with Deploy-If-Not-Exists (DINE) enabled for automatic Private DNS zone provisioning
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) v2.50+
- [Terraform](https://www.terraform.io/downloads) v1.10.x or later
- **(Optional)** [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/) (`azd`) v1.10+ for simplified environment management

### Required Network Configuration

These resource IDs must exist and be provided in your `terraform.tfvars`:

| Variable                      | Description                                                 | Example                                             |
| ----------------------------- | ----------------------------------------------------------- | --------------------------------------------------- |
| `container_apps_subnet_id`    | Pre-created subnet for Container Apps Environment (min /27) | `/subscriptions/.../subnets/snet-containerapps`     |
| `private_endpoints_subnet_id` | Pre-created subnet for all Private Endpoints                | `/subscriptions/.../subnets/snet-private-endpoints` |

### Required Permissions

The deploying identity (user or service principal) requires:

- **Key Vault Administrator** role (to assign RBAC roles and create secrets)
- **Contributor** role on target resource group and subscription
- Read access to existing VNet and subnets

## Configuration

### 1. Copy and Customize Variables

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

Edit `infra/terraform.tfvars` with your values:

| Variable Category         | Required Variables                                                             |
| ------------------------- | ------------------------------------------------------------------------------ |
| **Azure Basics**          | `subscription_id`, `resource_group_name`, `location`                           |
| **Networking**            | `container_apps_subnet_id`, `private_endpoints_subnet_id`                      |
| **GitLab Configuration**  | `gitlab_hostname`, `gitlab_root_password`, `gitlab_runner_token`               |
| **GitLab Image**          | `gitlab_image_repository`, `gitlab_image_tag`                                  |
| **Container Resources**   | `gitlab_cpu`, `gitlab_memory`, `workload_profile_type`                         |
| **Storage**               | `storage_account_replication_type`, `file_shares` (array)                      |
| **PostgreSQL**            | `postgresql_admin_password`, `postgresql_version`, `postgresql_sku_name`, etc. |
| **RBAC (Terraform only)** | `azure_principal_id` (auto-provided by azd; manual for direct Terraform)       |

### 2. Configure Terraform Backend

#### Option A: Backend Configuration File (Recommended)

Create `infra/backend.conf`:

```hcl
resource_group_name  = "rg-tfstate"
storage_account_name = "sttfstate12345"
container_name       = "tfstate"
key                  = "gitlab-on-aca.tfstate"
```

Then initialize:

```bash
cd infra
terraform init -backend-config=backend.conf
```

#### Option B: Inline Backend Configuration

```bash
cd infra
terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=sttfstate12345" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=gitlab-on-aca.tfstate"
```

#### Option C: Environment Variables for Authentication

```bash
export ARM_ACCESS_KEY="<storage-account-access-key>"
# Or use Azure CLI authentication (recommended):
az login
az account set --subscription <SUBSCRIPTION_ID>
```

### 3. Key Configuration Variables Explained

#### Resource Sizing

| Variable                | Options                                         | Recommendation                   |
| ----------------------- | ----------------------------------------------- | -------------------------------- |
| `workload_profile_type` | Consumption, D4, D8, D16, D32, E4, E8, E16, E32 | D8 (8 vCPU, 32GB) for production |
| `gitlab_cpu`            | Number (vCPU cores)                             | 4+ for production                |
| `gitlab_memory`         | String with Gi suffix (e.g., "8Gi")             | 8Gi minimum for production       |

**Note**: Workload profile must support the container's CPU/memory allocation. D8 supports up to 8 vCPU.

#### PostgreSQL Configuration

| Variable                                  | Dev Value         | Production Value     | Purpose                        |
| ----------------------------------------- | ----------------- | -------------------- | ------------------------------ |
| `postgresql_sku_name`                     | `B_Standard_B2ms` | `GP_Standard_D4s_v3` | Server size (2-4+ vCPU)        |
| `postgresql_storage_mb`                   | `32768` (32GB)    | `65536+` (64GB+)     | Storage capacity               |
| `postgresql_storage_tier`                 | `P4` or `P6`      | `P10+`               | IOPS performance               |
| `postgresql_backup_retention_days`        | `7`               | `14-35`              | Backup retention window        |
| `postgresql_geo_redundant_backup_enabled` | `false`           | `true`               | Cross-region backup redundancy |
| `postgresql_high_availability_mode`       | `Disabled`        | `ZoneRedundant`      | HA configuration               |

#### GitLab Image Configuration

```hcl
gitlab_image_repository = "gitlab/gitlab-ee"     # Source repository on Docker Hub
gitlab_image_tag        = "18.5.2-ee.0"          # Specific version tag (not "latest" for prod)
```

The deployment imports this image from Docker Hub into your private ACR, then deploys from ACR with image path:

```
<acr-login-server>/gitlab/gitlab-ee:18.5.2-ee.0
```

#### Bootstrap vs Production Probes

```hcl
gitlab_use_bootstrap_probes = true   # Extended timeouts for first-time setup
                                     # Set to false after successful initialization
```

**Bootstrap mode** (recommended for first deployment):

- Startup probe: 600s timeout, 60s period
- Liveness probe: 120s timeout, 60s period
- Readiness probe: 60s timeout, 30s period

**Production mode** (after GitLab is stable):

- Startup probe: 300s timeout, 30s period
- Liveness probe: 60s timeout, 30s period
- Readiness probe: 30s timeout, 15s period

## Data Persistence

GitLab data is persisted to **Azure Files Premium** (NFS 3.0 protocol) mounted to the container at runtime. Three file shares store configuration, application data (repositories, wiki, LFS), and logs.

### Default File Shares

| Share Name      | Quota | Container Mount Path | Purpose                                  |
| --------------- | ----- | -------------------- | ---------------------------------------- |
| `gitlab-config` | 100GB | `/etc/gitlab`        | Omnibus configuration files              |
| `gitlab-data`   | 500GB | `/var/opt/gitlab`    | Repositories, database, uploads, CI jobs |
| `gitlab-logs`   | 100GB | `/var/log/gitlab`    | Application and service logs             |

These are configurable via the `file_shares` array in `terraform.tfvars`.

### Storage Architecture

- **SKU**: Premium FileStorage (required for NFS features)
- **Replication**: LRS or ZRS (configurable via `storage_account_replication_type`)
- **Protocol**: NFS 3.0 (no SMB; `https_traffic_only_enabled = false`)
- **Access**: Storage account keys (identity-based mounting not supported for NFS)
- **Networking**: Private endpoint only; no public access

### Backup Considerations

Azure Files Premium supports:

- Snapshots (manual or scheduled)
- Azure Backup integration
- Cross-region replication (via `storage_account_replication_type = "ZRS"`)

For production deployments, configure backup policies for `gitlab-data` share to protect repositories and database.

## Deployment Options

This repository supports two deployment workflows:

1. **Azure Developer CLI (`azd`)** - Recommended for simplified environment management
2. **Direct Terraform** - For CI/CD pipelines or manual infrastructure control

---

## Option 1: Deployment with Azure Developer CLI (Recommended)

Azure Developer CLI simplifies environment variable management and automates Terraform backend configuration.

### Initial Setup

```bash
# 1. Authenticate to Azure
az login
azd auth login

# 2. Initialize azd environment
azd init

# When prompted:
# - Environment name: dev (or your choice)
# - Subscription: Select your target subscription

# 3. Configure required environment variables
azd env set AZURE_SUBSCRIPTION_ID "<your-subscription-id>"
azd env set AZURE_RESOURCE_GROUP "<your-resource-group>"
azd env set AZURE_LOCATION "eastus2"
azd env set CONTAINER_APPS_SUBNET_ID "<subnet-resource-id>"
azd env set PRIVATE_ENDPOINTS_SUBNET_ID "<subnet-resource-id>"
azd env set GITLAB_HOSTNAME "gitlab.yourdomain.com"
azd env set GITLAB_ROOT_PASSWORD "<secure-password>"
azd env set GITLAB_RUNNER_TOKEN "<runner-token>"
azd env set POSTGRESQL_ADMIN_PASSWORD "<db-password>"

# Note: azd automatically provides AZURE_PRINCIPAL_ID to Terraform
```

### Provision Infrastructure

```bash
# Full deployment (init + plan + apply)
azd up

# Or step-by-step:
azd provision  # Runs terraform init, plan, apply
```

### View Outputs

```bash
azd env get-values  # Show all environment variables
```

Terraform outputs available after deployment:

| Output Name                    | Description                           |
| ------------------------------ | ------------------------------------- |
| `gitlab_url`                   | Full HTTPS URL to GitLab web UI       |
| `gitlab_fqdn`                  | Container App FQDN                    |
| `acr_name`                     | Azure Container Registry name         |
| `acr_login_server`             | ACR login server URL                  |
| `storage_account_name`         | Storage account for file shares       |
| `key_vault_name`               | Key Vault name                        |
| `container_app_environment_id` | Container App Environment resource ID |
| `unique_suffix`                | Generated suffix for resource naming  |

### Update Infrastructure

```bash
# After modifying Terraform files:
azd provision
```

### Destroy Infrastructure

```bash
azd down --force --purge
```

---

## Option 2: Direct Terraform Deployment

Use this approach for CI/CD pipelines, automation, or when azd is not available.

### Prerequisites for Direct Terraform

1. Terraform backend storage account must exist
2. `infra/terraform.tfvars` must be fully populated
3. Azure authentication configured via Azure CLI or service principal

### Initial Deployment

```bash
# 1. Authenticate to Azure
az login
az account set --subscription <SUBSCRIPTION_ID>

# 2. Get your principal ID for Key Vault RBAC
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

# 3. Navigate to infrastructure directory
cd infra

# 4. Initialize Terraform with backend
terraform init -backend-config=backend.conf
# Or use inline configuration (see Configuration section above)

# 5. Validate configuration
terraform validate

# 6. Create execution plan
terraform plan \
  -var-file=terraform.tfvars \
  -var="azure_principal_id=$PRINCIPAL_ID" \
  -out=tfplan

# 7. Review plan output carefully, then apply
terraform apply tfplan
```

### Using Service Principal (CI/CD)

```bash
# Set authentication environment variables
export ARM_CLIENT_ID="<service-principal-app-id>"
export ARM_CLIENT_SECRET="<service-principal-password>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export ARM_TENANT_ID="<tenant-id>"

# Get service principal object ID
SP_OBJECT_ID=$(az ad sp show --id $ARM_CLIENT_ID --query id -o tsv)

# Run Terraform
cd infra
terraform init -backend-config=backend.conf
terraform plan \
  -var-file=terraform.tfvars \
  -var="azure_principal_id=$SP_OBJECT_ID" \
  -out=tfplan
terraform apply tfplan
```

### View Outputs

```bash
# All outputs as JSON
terraform output -json | jq

# Specific outputs
terraform output -raw gitlab_url
terraform output -raw acr_login_server
terraform output -raw key_vault_name
```

### Update Infrastructure

```bash
cd infra

# After modifying Terraform files or tfvars:
terraform plan \
  -var-file=terraform.tfvars \
  -var="azure_principal_id=$PRINCIPAL_ID" \
  -out=tfplan

terraform apply tfplan
```

### Destroy Infrastructure

```bash
cd infra

terraform destroy \
  -var-file=terraform.tfvars \
  -var="azure_principal_id=$PRINCIPAL_ID"

# Note: Remote state remains in Azure Storage; delete manually if needed
```

---

## Post-Deployment Steps

### 1. Monitor GitLab Initialization

GitLab takes 5-15 minutes to complete initial setup (Omnibus convergence).

```bash
# Get resource names from Terraform outputs
GITLAB_APP_NAME=$(terraform output -raw container_app_name 2>/dev/null || echo "ca-gitlab-<suffix>")
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null)

# Stream container logs
az containerapp logs show \
  --name "$GITLAB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --follow

# Or via Azure Portal: Container Apps > Logs > Console Logs
```

### 2. Access GitLab

```bash
# Get GitLab URL
terraform output -raw gitlab_url

# Or with azd:
azd env get-values | grep GITLAB_URL
```

Navigate to the URL and log in with:

- **Username**: `root`
- **Password**: Value from `gitlab_root_password` in tfvars

### 3. Verify Private Networking

```bash
# Test DNS resolution (should return private IP)
nslookup <storage-account-name>.file.core.windows.net

# Check private endpoints
az network private-endpoint list \
  --resource-group "$RESOURCE_GROUP" \
  --output table
```

### 4. Configure Custom Domain (Optional)

Update Container App with custom domain and certificate:

```bash
az containerapp hostname add \
  --name "$GITLAB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --hostname "gitlab.yourdomain.com"

# Add certificate (managed or bring-your-own)
az containerapp ssl upload \
  --name "$GITLAB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --certificate-file cert.pfx \
  --hostname "gitlab.yourdomain.com"
```

Then update `gitlab_hostname` in tfvars and re-apply Terraform.

## Troubleshooting

### Common Deployment Issues

| Issue                                  | Cause                                        | Solution                                                                |
| -------------------------------------- | -------------------------------------------- | ----------------------------------------------------------------------- |
| **Container App activation fails**     | Probe failures during Omnibus convergence    | Wait 10-15 min; check logs; verify `gitlab_use_bootstrap_probes = true` |
| **Private endpoint DNS not resolving** | Azure Policy DINE not provisioned            | Verify policy is enabled; wait 5-10 min for propagation                 |
| **Key Vault access denied**            | RBAC propagation delay                       | Wait 60s; verify `azure_principal_id` matches deploying identity        |
| **Storage mount failing**              | Private endpoint not ready                   | Check PE status; verify NSG allows port 2049 (NFS)                      |
| **GitLab 502/503 errors**              | Internal services still converging           | Normal during first 5-10 min; monitor logs                              |
| **Terraform backend init fails**       | Storage account auth issue                   | Verify `ARM_ACCESS_KEY` or Azure CLI authentication                     |
| **`azure_principal_id` not provided**  | Running direct Terraform without setting var | Pass via `-var="azure_principal_id=$PRINCIPAL_ID"` or add to tfvars     |

### Debug Commands

```bash
# Check container app status
az containerapp show \
  --name "$GITLAB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "properties.{status:provisioningState,health:runningStatus}" -o table

# View recent logs (max 300 lines via CLI)
az containerapp logs show \
  --name "$GITLAB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --tail 300

# For more logs, query Log Analytics workspace
LOG_ANALYTICS_ID=$(terraform output -raw log_analytics_workspace_id)
az monitor log-analytics query \
  --workspace "$LOG_ANALYTICS_ID" \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == '$GITLAB_APP_NAME' | order by TimeGenerated desc | take 1000"

# Check private endpoint DNS
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
nslookup "${STORAGE_ACCOUNT}.file.core.windows.net"

# Verify file share mounts
az containerapp env storage list \
  --name "cae-gitlab-<suffix>" \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# Check Key Vault secrets
KEY_VAULT=$(terraform output -raw key_vault_name)
az keyvault secret list --vault-name "$KEY_VAULT" --output table
```

### GitLab-Specific Issues

| Issue                            | Solution                                                           |
| -------------------------------- | ------------------------------------------------------------------ |
| **Slow initial startup**         | Expected; Omnibus convergence + data initialization takes 5-15 min |
| **Health probes failing**        | Verify probes use port 8080 and HTTP (not HTTPS)                   |
| **HTTPS redirect loop**          | Ensure `nginx['redirect_http_to_https']=false` in Omnibus config   |
| **ACME/Let's Encrypt errors**    | Disable in Omnibus config; use Container Apps managed certificates |
| **Repository push/pull failing** | Check storage mount; verify NFS connectivity to Azure Files        |

### Terraform-Specific Issues

```bash
# Refresh state if resources manually changed
terraform refresh -var-file=terraform.tfvars

# Import existing resource (if needed)
terraform import <resource_type>.<name> <azure_resource_id>

# Force unlock if state locked
terraform force-unlock <lock-id>

# Validate configuration syntax
terraform validate

# Check for provider updates
terraform init -upgrade
```

---

## Advanced Topics

### CI/CD Pipeline Integration

Example GitHub Actions workflow for automated deployment:

```yaml
name: Deploy GitLab Infrastructure

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.10.0

      - name: Terraform Init
        working-directory: ./infra
        run: |
          terraform init \
            -backend-config="resource_group_name=${{ secrets.TF_STATE_RG }}" \
            -backend-config="storage_account_name=${{ secrets.TF_STATE_SA }}" \
            -backend-config="container_name=tfstate" \
            -backend-config="key=gitlab-on-aca.tfstate"

      - name: Terraform Plan
        working-directory: ./infra
        run: |
          terraform plan \
            -var-file=terraform.tfvars \
            -var="azure_principal_id=${{ secrets.SP_OBJECT_ID }}" \
            -out=tfplan

      - name: Terraform Apply
        working-directory: ./infra
        run: terraform apply -auto-approve tfplan
```

### Scaling Considerations

**Current Limitations**:

- **Single replica only**: GitLab EE shared storage architecture
- **Vertical scaling**: Increase `gitlab_cpu`, `gitlab_memory`, and `workload_profile_type`
- **Storage scaling**: Increase file share quotas in `file_shares` array

**For Multi-Replica Support**:

- Consider GitLab Helm chart on AKS with external PostgreSQL and Redis
- Use Azure Database for PostgreSQL and Azure Cache for Redis
- Enable GitLab Object Storage with Azure Blob Storage

### Monitoring and Alerts

Key metrics to monitor:

```bash
# Container App metrics via Azure Monitor
az monitor metrics list \
  --resource "$CONTAINER_APP_ID" \
  --metric-names "Requests,ResponseTime,CpuUsage,MemoryUsage" \
  --start-time "2025-01-01T00:00:00Z"

# Set up metric alerts
az monitor metrics alert create \
  --name "gitlab-high-cpu" \
  --resource-group "$RESOURCE_GROUP" \
  --scopes "$CONTAINER_APP_ID" \
  --condition "avg CpuUsage > 80" \
  --description "Alert when CPU exceeds 80%"
```

Recommended alerts:

- CPU utilization > 80%
- Memory utilization > 85%
- Container restarts > 3 in 5 minutes
- HTTP 5xx errors > 10 in 1 minute

### Security Hardening

**Production Checklist**:

- [ ] Enable Azure Policy for compliance scanning
- [ ] Configure Network Security Groups with minimal required ports
- [ ] Rotate secrets in Key Vault regularly
- [ ] Enable diagnostic settings on all resources
- [ ] Use Azure Defender for Container Apps
- [ ] Implement custom domain with TLS certificate
- [ ] Configure Azure AD SSO for GitLab authentication
- [ ] Enable audit logging for Key Vault and Container Apps
- [ ] Use managed identity instead of storage keys where possible
- [ ] Implement Azure Firewall for egress traffic control

### Cost Optimization

**Development Environment**:

```hcl
workload_profile_type                = "D4"              # $140/month
postgresql_sku_name                  = "B_Standard_B2ms" # $50/month
storage_account_replication_type     = "LRS"            # $0.05/GB/month
postgresql_high_availability_mode    = "Disabled"       # No HA cost
```

**Production Environment**:

```hcl
workload_profile_type                = "D8"                 # $280/month
postgresql_sku_name                  = "GP_Standard_D4s_v3" # $200/month
storage_account_replication_type     = "ZRS"               # $0.06/GB/month
postgresql_high_availability_mode    = "ZoneRedundant"     # +100% DB cost
```

Use Azure Cost Management to monitor spending and set budgets.

### Module Documentation

Detailed module documentation available in:

- `infra/modules/container-app/` - GitLab container app configuration
- `infra/modules/storage-account/` - Azure Files Premium setup
- `infra/modules/acr/` - Private container registry
- `infra/modules/postgresql/` - Flexible Server configuration
- `infra/modules/private-endpoint/` - Private endpoint provisioning
- `infra/modules/key-vault/` - Secret management

Each module includes `README.md` or inline documentation.

## Links

- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [GitLab Docker](https://docs.gitlab.com/ee/install/docker.html)
- [Azure Files NFS](https://learn.microsoft.com/azure/storage/files/storage-files-how-to-create-nfs-shares)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)

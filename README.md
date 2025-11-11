# GitLab on Azure Container Apps

This repository provisions a fully private Azure Container Apps deployment running the official `gitlab/gitlab-ee` image. All Azure resources are created **exclusively via Terraform** which is orchestrated by the Azure Developer CLI (`azd`) hooks defined in `azure.yaml`.

> Infrastructure includes: Container Apps Environment (VNet integrated + Dedicated workload profile), GitLab Container App, Azure Files (NFS) share mounts, ACR (Premium, private endpoint), Key Vault, Log Analytics, Application Insights, Managed Identity, Private Endpoints (Storage, ACR, Key Vault), and required NSGs. Private DNS zones are **NOT** manually created (auto-managed by Azure Policy DINE).

## Architecture

![architecture](./.img/architecture.png)

## Disclaimer

**THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.**

## Prerequisites

You must have the following before provisioning:

- Azure subscription
- **Existing Resource Group** (referenced in tfvars; Terraform will not create it)
- **Existing Azure Storage Account + Blob Container** for Terraform remote state (configure during `terraform init`)
- Existing VNet with: Container Apps subnet & Private Endpoints subnet (resource IDs required)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/) (`azd`) v1.0+ (optional)
- Terraform v1.10.x

### Network Inputs Required

These resource IDs are referenced (not created) by Terraform via your `terraform.tfvars`:

| Variable                      | Description                                       |
| ----------------------------- | ------------------------------------------------- |
| `container_apps_subnet_id`    | Pre-created subnet for Container Apps Environment |
| `private_endpoints_subnet_id` | Pre-created subnet for all Private Endpoints      |

## Configuration

1. Copy template variables file:
   ```bash
   cp infra/terraform.tfvars.example infra/terraform.tfvars
   ```
2. Edit `infra/terraform.tfvars` and set: subscription id, resource group name (must exist), location, network resource IDs, GitLab hostname, and secrets (use Key Vault in production; plain text only for initial testing).
3. **Configure remote state backend** (Azure Storage Account):

   ```bash
   # Option 1: Use CLI arguments during terraform init
   cd infra
   terraform init \
     -backend-config="resource_group_name=<rg-tfstate>" \
     -backend-config="storage_account_name=<sa-tfstate>" \
     -backend-config="container_name=tfstate" \
     -backend-config="key=gitlab-on-aca.tfstate"

   # Option 2: Set environment variables for authentication
   export ARM_ACCESS_KEY="<storage-account-key>"
   # Or use Azure CLI authentication (recommended):
   az login
   terraform init  # Will prompt for backend config or use partial config file
   ```

Secrets such as `gitlab_root_password` should ultimately be sourced from Key Vault; the Terraform code already provisions a vault. Replace inline secrets with secure references once initialized.## GitLab Data Persistence

Azure Files NFS share mounts three paths inside the container:
`/etc/gitlab`, `/var/opt/gitlab`, `/var/log/gitlab` for config, application data (repos), and logs respectively.

## Provisioning with Terraform

All infrastructure is provisioned via Terraform. Azure Developer CLI (`azd`) is optional and only used for convenience (environment variable management).

### End-to-End Deployment

```bash
# 1. Authenticate to Azure
az login
az account set --subscription <SUBSCRIPTION_ID>

# 2. Verify tfvars and backend storage account exist
test -f infra/terraform.tfvars || echo "Missing infra/terraform.tfvars"

# 3. Initialize Terraform with remote backend
cd infra
terraform init \
  -backend-config="resource_group_name=<rg-tfstate>" \
  -backend-config="storage_account_name=<sa-tfstate>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=gitlab-on-aca.tfstate"

# 4. Validate and plan
terraform validate
terraform plan -var-file=terraform.tfvars -out=tfplan

# 5. Apply infrastructure
terraform apply tfplan

# 6. Retrieve outputs
terraform output -json | jq
terraform output -raw gitlab_url
```

During provisioning:

1. Terraform creates Container Apps Environment, GitLab Container App, Azure Files NFS storage, ACR, Key Vault, Log Analytics, Application Insights, Managed Identity, Private Endpoints, and NSGs
2. Private DNS zones are automatically created by Azure Policy (DINE) — do not create manually
3. Initial GitLab startup may take 5–10 minutes

Monitor GitLab initialization:

```bash
GITLAB_APP_NAME=$(terraform output -raw container_app_name 2>/dev/null || echo "ca-gitlab-<suffix>")
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || grep resource_group_name terraform.tfvars | cut -d'"' -f2)

az containerapp logs show \
  --name "$GITLAB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --follow
```

## Updating / Destroying

To re-apply infrastructure after changes:

```bash
cd infra
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

To tear everything down:

```bash
cd infra
terraform destroy -var-file=terraform.tfvars
# Note: Remote state will remain in Azure Storage; delete manually if needed
```

## Troubleshooting

- Container App failing start: check volume mounts & NFS settings.
- Private endpoints DNS: rely on Azure Policy DINE (do **not** create zones manually).
- Slow first boot: GitLab initialization (expected).

## Links

- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [GitLab Docker](https://docs.gitlab.com/ee/install/docker.html)
- [Azure Files NFS](https://learn.microsoft.com/azure/storage/files/storage-files-how-to-create-nfs-shares)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)

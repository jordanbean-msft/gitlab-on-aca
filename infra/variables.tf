variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}
variable "resource_group_name" {
  description = "Existing resource group name"
  type        = string
}
variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}
variable "unique_suffix" {
  description = "Optional unique suffix override"
  type        = string
  default     = ""
}
variable "container_apps_subnet_id" {
  description = "Existing subnet ID for Azure Container Apps environment infrastructure/workload profile"
  type        = string
}
variable "private_endpoints_subnet_id" {
  description = "Existing subnet ID dedicated to Private Endpoints"
  type        = string
}
variable "postgresql_admin_password" {
  description = "PostgreSQL administrator password"
  type        = string
  sensitive   = true
}
variable "postgresql_version" {
  description = "PostgreSQL version (16 or 17)"
  type        = string
}
variable "postgresql_administrator_login" {
  description = "PostgreSQL administrator login name"
  type        = string
}
variable "postgresql_sku_name" {
  description = "PostgreSQL SKU name (e.g., B_Standard_B2ms, GP_Standard_D4s_v3)"
  type        = string
}
variable "postgresql_storage_mb" {
  description = "PostgreSQL storage size in MB (minimum 32768 for 32 GB)"
  type        = number
}
variable "postgresql_storage_tier" {
  description = "PostgreSQL storage performance tier (P4, P6, P10, P15, P20, P30, P40, P50)"
  type        = string
}
variable "postgresql_backup_retention_days" {
  description = "PostgreSQL backup retention in days"
  type        = number
}
variable "postgresql_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups for PostgreSQL"
  type        = bool
}
variable "postgresql_high_availability_mode" {
  description = "PostgreSQL high availability mode (Disabled, SameZone, ZoneRedundant)"
  type        = string
}
variable "postgresql_zone" {
  description = "PostgreSQL availability zone"
  type        = string
}
variable "postgresql_location" {
  description = "Region for PostgreSQL Flexible Server (defaults to location if empty)"
  type        = string
  default     = ""
}
variable "gitlab_hostname" {
  description = "Public hostname for GitLab external_url"
  type        = string
}
variable "gitlab_root_password" {
  description = "Initial root password (pulled from Key Vault in practice)"
  type        = string
  sensitive   = true
}
variable "gitlab_runner_token" {
  description = "Registration token for shared runners"
  type        = string
  sensitive   = true
}
variable "tags" {
  description = "Base tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (e.g. LRS, ZRS)"
  type        = string
}

variable "workload_profile_type" {
  description = "Container Apps Environment workload profile type (Consumption, D4, D8, D16, D32, E4, E8, E16, E32)"
  type        = string
  default     = "D4"

  validation {
    condition     = contains(["Consumption", "D4", "D8", "D16", "D32", "E4", "E8", "E16", "E32"], var.workload_profile_type)
    error_message = "workload_profile_type must be one of: Consumption, D4, D8, D16, D32, E4, E8, E16, E32"
  }
}

variable "workload_profile_name" {
  description = "Container Apps workload profile name (<16 chars). Default shortened to meet naming rules."
  type        = string
  default     = "gitlabded"

  validation {
    condition     = length(var.workload_profile_name) < 16
    error_message = "workload_profile_name must be less than 16 characters."
  }
}

variable "azure_principal_id" {
  description = "Principal ID (object ID) of identity running azd (AZURE_PRINCIPAL_ID) for Key Vault RBAC grant"
  type        = string
}

variable "file_shares" {
  description = "List of Azure Files shares to create with name, quota (GiB), and container mount path"
  type = list(object({
    name  = string
    quota = number
    path  = string
  }))
  default = [
    { name = "gitlab-config", quota = 100, path = "/etc/gitlab" },
    { name = "gitlab-data", quota = 500, path = "/var/opt/gitlab" },
    { name = "gitlab-logs", quota = 100, path = "/var/log/gitlab" }
  ]
}

# GitLab container sizing (override for bootstrap if desired)
variable "gitlab_cpu" {
  description = "vCPU cores allocated to GitLab container (set in terraform.tfvars)"
  type        = number
}

variable "gitlab_memory" {
  description = "Memory allocated to GitLab container (Gi suffix, set in terraform.tfvars)"
  type        = string
}

variable "gitlab_use_bootstrap_probes" {
  description = "If true, apply extended probe timings for first-time Omnibus convergence. Set to false after initial setup for tighter health checks."
  type        = bool
  default     = true
}

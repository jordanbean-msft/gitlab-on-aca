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

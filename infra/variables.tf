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

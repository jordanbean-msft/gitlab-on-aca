variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment_id" { type = string }
variable "image" { type = string }
variable "cpu" { type = number }
variable "memory" { type = string }
variable "min_replicas" { type = number }
variable "max_replicas" { type = number }
variable "target_port" { type = number }
variable "external_enabled" { type = bool }
variable "registry_server" { type = string }
variable "registry_identity_id" { type = string }
variable "identity_ids" { type = list(string) }
variable "gitlab_hostname" { type = string }
variable "key_vault_secret_id_password" {
  type        = string
  description = "Key Vault secret ID for GitLab root password"
}
variable "key_vault_secret_id_token" {
  type        = string
  description = "Key Vault secret ID for GitLab runner token"
}
variable "postgresql_host" {
  type        = string
  description = "PostgreSQL server FQDN"
}
variable "postgresql_database" {
  type        = string
  description = "PostgreSQL database name"
}
variable "key_vault_secret_id_db_username" {
  type        = string
  description = "Key Vault secret ID for PostgreSQL admin username"
}
variable "key_vault_secret_id_db_password" {
  type        = string
  description = "Key Vault secret ID for PostgreSQL admin password"
}
variable "storage_account_name" { type = string }
variable "storage_account_key" {
  type        = string
  sensitive   = true
  description = "Storage account primary access key for Azure Files mounting"
}
variable "file_shares" {
  description = "List of file shares with name and mount path"
  type = list(object({
    name = string
    path = string
  }))
}
variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostic settings"
  type        = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

# Toggle for extended bootstrap probe profile (slow first GitLab converge)
variable "use_bootstrap_probes" {
  type        = bool
  default     = true
  description = "If true, use extended, lenient probe timings to allow initial GitLab Omnibus convergence without premature restarts. Switch to false after first successful initialization for tighter health checks."
}

variable "workload_profile_name" {
  description = "Name of the workload profile to assign this container app to (must match environment workload profile)"
  type        = string
}

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
variable "tags" {
  type    = map(string)
  default = {}
}

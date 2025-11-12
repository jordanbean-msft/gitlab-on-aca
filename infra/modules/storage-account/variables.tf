variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostic settings"
  type        = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "account_replication_type" {
  description = "Replication type (e.g. LRS, ZRS) - set via tfvars"
  type        = string
}

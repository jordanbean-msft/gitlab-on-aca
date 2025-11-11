variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "infrastructure_subnet_id" { type = string }
variable "workload_profile_type" {
  type        = string
  description = "Workload profile type (Consumption, D4, D8, D16, D32, E4, E8, E16, E32)"
}
variable "workload_profile_name" {
  type        = string
  description = "Workload profile name (<=15 chars, lowercase alphanumeric and dashes)"
  default     = "gitlabded"
}
variable "tags" {
  type    = map(string)
  default = {}
}

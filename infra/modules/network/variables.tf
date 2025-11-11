variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "unique_suffix" { type = string }
variable "container_apps_subnet_id" { type = string }
variable "private_endpoints_subnet_id" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

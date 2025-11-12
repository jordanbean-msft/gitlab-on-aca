variable "name" {
  description = "Name of the PostgreSQL Flexible Server"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "postgresql_version" {
  description = "PostgreSQL version (16 or 17)"
  type        = string
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled (required true for private endpoint creation, will be disabled post-PE if desired)"
  type        = bool
}

variable "administrator_login" {
  description = "Administrator login name"
  type        = string
}

variable "administrator_password" {
  description = "Administrator password"
  type        = string
  sensitive   = true
}

variable "sku_name" {
  description = "SKU name for the PostgreSQL server (e.g., B_Standard_B2ms, GP_Standard_D4s_v3)"
  type        = string
}

variable "storage_mb" {
  description = "Storage size in MB (minimum 32768 for 32 GB)"
  type        = number
}

variable "storage_tier" {
  description = "Storage performance tier (P4, P6, P10, P15, P20, P30, P40, P50)"
  type        = string
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
}

variable "geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups"
  type        = bool
}

variable "high_availability_mode" {
  description = "High availability mode (Disabled, SameZone, ZoneRedundant)"
  type        = string
}

variable "zone" {
  description = "Availability zone (still valid when using public access)"
  type        = string
}

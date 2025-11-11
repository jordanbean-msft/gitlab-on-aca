variable "name" { type = string }
variable "storage_account_name" { type = string }
variable "quota" {
  type = number
  # GitLab recommendation: start >= 500 GiB; adjust based on expected repo/storage growth
  default = 500
}

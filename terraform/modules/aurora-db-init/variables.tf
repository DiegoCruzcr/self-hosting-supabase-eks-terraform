variable "aurora_host" {
  description = "Aurora cluster writer endpoint"
  type        = string
}

variable "project_name" {
  description = "Supabase project/tenant name; used as the PostgreSQL database name"
  type        = string
}

variable "master_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Aurora master password"
  type        = string
  sensitive   = false
}

variable "authenticator_password" {
  description = "Password for the authenticator role (used by PostgREST)"
  type        = string
  sensitive   = false
}

variable "auth_password" {
  description = "Password for the supabase_auth_admin role (used by GoTrue)"
  type        = string
  sensitive   = false
}

variable "storage_password" {
  description = "Password for the supabase_storage_admin role (used by Storage API)"
  type        = string
  sensitive   = false
}

variable "realtime_password" {
  description = "Password for the supabase_realtime_admin role (used by Realtime)"
  type        = string
  sensitive   = false
}

variable "admin_password" {
  description = "Password for the supabase_admin_user role (used by pg-meta and Studio)"
  type        = string
  sensitive   = false
}

variable "reboot_complete_trigger" {
  description = "Value from aurora module's reboot null_resource; ensures DB init runs after reboot"
  type        = string
}

variable "aws_region" {
  description = "AWS region (for fetching master password from Secrets Manager)"
  type        = string
  default     = "us-east-1"
}

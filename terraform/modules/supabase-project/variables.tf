variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Supabase project/tenant name; used as namespace, DB name, S3 bucket prefix"
  type        = string
}

variable "jwt_secret" {
  description = "JWT signing secret (min 32 chars)"
  type        = string
  sensitive   = false
}

variable "anon_key" {
  description = "JWT token signed with jwt_secret, role=anon"
  type        = string
  sensitive   = false
}

variable "service_key" {
  description = "JWT token signed with jwt_secret, role=service_role"
  type        = string
  sensitive   = false
}

variable "authenticator_password" {
  description = "Password for the authenticator PostgreSQL role"
  type        = string
  sensitive   = false
}

variable "studio_password" {
  description = "Studio (Supabase dashboard) login password"
  type        = string
  sensitive   = false
}

variable "realtime_enc_key" {
  description = "Realtime encryption key (min 32 chars)"
  type        = string
  sensitive   = false
}

variable "realtime_secret_key_base" {
  description = "Realtime Phoenix SECRET_KEY_BASE (min 64 chars)"
  type        = string
  sensitive   = false
}

variable "cluster_oidc_provider_arn" {
  description = "ARN of the EKS OIDC identity provider (for IRSA)"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster (for IRSA trust policy)"
  type        = string
}

variable "external_url" {
  description = "Publicly reachable base URL for this project (used for Studio, Auth, Kong ingress host). E.g. http://<alb-dns> or https://myproject.example.com"
  type        = string
}

variable "vault_enc_key" {
  description = "32-char hex key for pgsodium/Supabase Vault (VAULT_ENC_KEY in postgres container). Generate with: openssl rand -hex 16"
  type        = string
  sensitive   = false
}

variable "meta_crypto_key" {
  description = "32-char hex key used by pg-meta (CRYPTO_KEY) and Studio (PG_META_CRYPTO_KEY) to encrypt/decrypt connection strings. Generate with: openssl rand -hex 16"
  type        = string
  sensitive   = false
}

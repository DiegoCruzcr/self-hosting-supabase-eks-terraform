variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "supabase-eks"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 4
}

variable "projects" {
  description = "List of Supabase project/tenant definitions. Pass via TF_VAR_projects env var — do NOT commit real secrets."
  sensitive   = false
  type = list(object({
    name                     = string
    jwt_secret               = string
    anon_key                 = string
    service_key              = string
    authenticator_password   = string
    realtime_enc_key         = string
    realtime_secret_key_base = string
    studio_password          = string
    external_url             = string
    vault_enc_key            = string
    meta_crypto_key          = string
    logflare_public_token    = string
    logflare_private_token   = string
  }))
}

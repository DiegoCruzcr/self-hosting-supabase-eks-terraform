variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name; also used for subnet tags"
  type        = string
  default     = "supabase-eks"
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version (e.g. 15.12)"
  type        = string
  # default     = "15.12"
}

variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs (0.5 minimum)"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs"
  type        = number
  default     = 8
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
  description = "List of Supabase project/tenant definitions"
  sensitive   = false
  type = list(object({
    name                     = string
    jwt_secret               = string # min 32 chars
    anon_key                 = string # JWT signed with jwt_secret, role=anon
    service_key              = string # JWT signed with jwt_secret, role=service_role
    authenticator_password   = string
    auth_password            = string
    storage_password         = string
    realtime_password        = string
    admin_password           = string
    realtime_enc_key         = string # min 32 chars
    realtime_secret_key_base = string # min 64 chars
    studio_password          = string
  }))
}

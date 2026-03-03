variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "db_subnet_group_name" {
  description = "RDS DB subnet group name"
  type        = string
}

variable "node_security_group_id" {
  description = "EKS node security group ID; Aurora allows inbound 5432 from this SG"
  type        = string
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  # default     = "15.12"
}

variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs"
  type        = number
  default     = 8
}

variable "first_project_name" {
  description = "Name of the first project; used for pg_cron cron.database_name parameter"
  type        = string
}

variable "publicly_accessible" {
  description = "Make Aurora publicly accessible from the internet. Requires db_subnet_group_name to point to public subnets."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to Aurora on port 5432. Only used when publicly_accessible = true. Use your PC's IP in /32 notation for security."
  type        = list(string)
  default     = ["0.0.0.0/0"] # restrict to your IP in production: ["203.0.113.42/32"]
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

# output "eks_cluster_endpoint" {
#   description = "EKS cluster API endpoint"
#   value       = module.eks.cluster_endpoint
# }

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}

output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = module.aurora.cluster_endpoint
}

output "aurora_master_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Aurora master password"
  value       = module.aurora.master_secret_arn
  sensitive   = false
}

output "project_namespaces" {
  description = "Kubernetes namespaces created for each Supabase project"
  value       = [for p in var.projects : "supabase-${p.name}"]
}

output "project_alb_hostnames" {
  description = "Expected ALB hostnames per project (configure DNS to point to ALB)"
  value       = [for p in var.projects : "${p.name}.example.com"]
}

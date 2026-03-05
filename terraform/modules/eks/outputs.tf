output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (used for IRSA)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the OIDC identity provider for IRSA"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "node_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.nodes.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "efs_file_system_id" {
  description = "EFS file system ID for edge functions (RWX storage)"
  value       = aws_efs_file_system.functions.id
}

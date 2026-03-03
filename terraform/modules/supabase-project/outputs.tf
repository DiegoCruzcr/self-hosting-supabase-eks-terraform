output "namespace" {
  description = "Kubernetes namespace for this Supabase project"
  value       = "supabase-${var.project_name}"
}

output "s3_bucket_name" {
  description = "S3 bucket name for Storage API"
  value       = aws_s3_bucket.storage.id
}

output "storage_irsa_role_arn" {
  description = "IAM role ARN for Storage API IRSA"
  value       = aws_iam_role.storage_irsa.arn
}

output "helm_release_status" {
  description = "Status of the Helm release"
  value       = helm_release.supabase.status
}

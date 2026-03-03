output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint (use this for all Supabase services)"
  value       = aws_rds_cluster.supabase.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.supabase.reader_endpoint
}

output "cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.supabase.id
}

output "security_group_id" {
  description = "Aurora security group ID"
  value       = aws_security_group.aurora.id
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Aurora master password"
  value       = aws_rds_cluster.supabase.master_user_secret[0].secret_arn
}

output "reboot_id" {
  description = "ID of the reboot null_resource; used as a depends_on trigger for db-init"
  value       = null_resource.aurora_reboot.id
}

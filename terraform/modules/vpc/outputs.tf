output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "db_subnet_group_name" {
  description = "Name of the Aurora DB subnet group (private subnets)"
  value       = aws_db_subnet_group.aurora.name
}

output "public_db_subnet_group_name" {
  description = "Name of the Aurora DB subnet group using public subnets (for publicly_accessible = true)"
  value       = aws_db_subnet_group.aurora_public.name
}

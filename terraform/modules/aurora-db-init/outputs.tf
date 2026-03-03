output "db_init_id" {
  description = "ID of the db-init null_resource; use as a depends_on trigger for Helm releases"
  value       = null_resource.db_init.id
}

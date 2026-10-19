output "db_identifier" {
  description = "DB instance identifier."
  value       = module.postgres.identifier
}

output "db_address" {
  description = "Private endpoint. Applications build DATABASE_URL from it (see docs/runbook.md)."
  value       = module.postgres.address
}

output "db_port" {
  description = "PostgreSQL port."
  value       = module.postgres.port
}

output "db_name" {
  description = "Initial database."
  value       = module.postgres.db_name
}

output "db_master_secret_arn" {
  description = "RDS-managed master credentials (keys: username, password). Used only by the db-admin task."
  value       = module.postgres.master_user_secret_arn
}

output "db_allocated_storage" {
  description = "Initial storage in GB."
  value       = module.postgres.allocated_storage
}

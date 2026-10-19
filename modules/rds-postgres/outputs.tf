output "identifier" {
  description = "DB instance identifier."
  value       = aws_db_instance.this.identifier
}

output "arn" {
  description = "DB instance ARN."
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "Private endpoint hostname."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database."
  value       = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret (keys: username, password) that RDS manages for the master user."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "allocated_storage" {
  description = "Initial storage in GB, for the free-storage alarm."
  value       = var.allocated_storage
}

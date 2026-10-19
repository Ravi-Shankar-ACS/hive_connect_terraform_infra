variable "identifier" {
  description = "DB instance identifier, for example hive-uat-postgres."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version. RDS picks the latest minor and keeps it patched."
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "Instance class."
  type        = string
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  description = "Initial gp3 storage in GB."
  type        = number
  default     = 50
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB."
  type        = number
  default     = 200
}

variable "multi_az" {
  description = "Standby in a second AZ (+$67.59 a month). Off for UAT."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Database created with the instance."
  type        = string
}

variable "master_username" {
  description = "Master user. Its password is generated and kept in Secrets Manager by RDS."
  type        = string
}

variable "subnet_ids" {
  description = "Data subnets (no internet route), in two or more AZs."
  type        = list(string)
}

variable "security_group_ids" {
  description = "db-sg."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for storage, snapshots and Performance Insights."
  type        = string
}

variable "master_secret_kms_key_arn" {
  description = "KMS key for the RDS-managed master password secret."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for the exported PostgreSQL log groups."
  type        = string
}

variable "backup_retention_days" {
  description = "Point-in-time recovery window."
  type        = number
  default     = 14
}

variable "backup_window" {
  description = "Daily backup window (UTC). Default is 00:00-01:00 IST."
  type        = string
  default     = "18:30-19:30"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC). Default is Monday 01:30-02:30 IST."
  type        = string
  default     = "sun:20:00-sun:21:00"
}

variable "deletion_protection" {
  description = "Block deletion of the instance."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on delete. Only for throwaway test databases."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply changes now instead of in the maintenance window."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the exported PostgreSQL logs."
  type        = number
  default     = 30
}

variable "parameters" {
  description = "Extra PostgreSQL parameters (name => value), merged over the defaults."
  type        = map(string)
  default     = {}
}

variable "permissions_boundary_arn" {
  description = "Permission boundary for the Enhanced Monitoring role."
  type        = string
}

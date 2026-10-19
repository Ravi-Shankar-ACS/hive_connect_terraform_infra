variable "name" {
  description = "Cluster name, for example hive-uat."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key that encrypts ECS Exec sessions and their log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for ECS Exec session logs."
  type        = number
  default     = 30
}

variable "container_insights" {
  description = "Container Insights adds roughly $15-20 a month of custom metrics, so it is off. Alarms use free ALB metrics and ECS events instead."
  type        = bool
  default     = false
}

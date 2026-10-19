variable "name" {
  description = "Name prefix, for example hive-uat."
  type        = string
}

variable "alert_emails" {
  description = "Addresses subscribed to the alert topic. A Slack or Teams channel's email address works for chat. Each must confirm the subscription email."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the SNS topic."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix."
  type        = string
}

variable "nat_gateway_id" {
  description = "NAT gateway ID."
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "db_allocated_storage_gb" {
  description = "RDS storage in GB; the free-storage alarm fires below 20% of it."
  type        = number
}

variable "cluster_arn" {
  description = "ECS cluster ARN, for service and deployment events."
  type        = string
}

variable "alb_5xx_threshold" {
  description = "5xx responses in 5 minutes that raise an alarm."
  type        = number
  default     = 10
}

variable "db_connections_threshold" {
  description = "Alarm above this many database connections (pool size x tasks should stay under ~100)."
  type        = number
  default     = 80
}

variable "db_cpu_credit_balance_threshold" {
  description = "Alarm when the db.t4g CPU credit balance falls below this."
  type        = number
  default     = 50
}

variable "db_iops_threshold" {
  description = "Alarm when read + write IOPS stay above this (gp3 ceiling is 3,000 below 400 GiB)."
  type        = number
  default     = 2400
}

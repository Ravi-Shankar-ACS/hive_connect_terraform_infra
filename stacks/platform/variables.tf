variable "domain_name" {
  description = "Existing public hosted zone, for example iotiqinnovations.com."
  type        = string
}

variable "services" {
  description = "The services and the hostname each one answers on. Keys must match envs/<env>/apps.tfvars."
  type = map(object({
    hostname = string
  }))
}

variable "dns_weight" {
  description = "Null for simple alias records. At production cutover, a weight (0-255) for weighted records next to the old ALB's."
  type        = number
  default     = null
}

variable "waf_block_mode" {
  description = "False = every WAF rule in Count mode (first UAT week). True = block."
  type        = bool
}

variable "waf_rate_limit" {
  description = "Requests per IP per 5 minutes before the rate rule acts."
  type        = number
  default     = 2000
}

variable "alb_idle_timeout" {
  description = "Seconds an idle connection (including a WebSocket) stays open."
  type        = number
  default     = 60
}

variable "alb_deletion_protection" {
  description = "Protect the ALB from deletion."
  type        = bool
  default     = true
}

variable "app_buckets" {
  description = "Application buckets to create; each becomes hive-<env>-<name>-<account id>."
  type        = list(string)
}

variable "secrets" {
  description = "Secrets the applications read at start: short name => what it holds. Terraform creates them empty; values are set by hand (docs/runbook.md) so they never enter Terraform state."
  type        = map(string)
}

variable "secret_recovery_days" {
  description = "Days a deleted secret can still be restored."
  type        = number
  default     = 7
}

variable "iot_topic_prefix" {
  description = "Topic prefix for this environment inside the existing IoT Core. Null skips the IoT device policy."
  type        = string
  default     = null
}

variable "alert_emails" {
  description = "Addresses (people or a chat channel's email address) that receive every alarm and the budget alerts."
  type        = list(string)
}

variable "monthly_budget_usd" {
  description = "Monthly budget before tax."
  type        = number
}

variable "log_retention_days" {
  description = "Retention for ECS Exec session logs."
  type        = number
  default     = 30
}

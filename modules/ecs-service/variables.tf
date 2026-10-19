variable "name" {
  description = "Service and container name, for example hiveconnect-api."
  type        = string
}

variable "name_prefix" {
  description = "Environment prefix, for example hive-uat."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "cluster_arn" {
  description = "ECS cluster ARN."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the target group."
  type        = string
}

variable "subnet_ids" {
  description = "Private app subnets."
  type        = list(string)
}

variable "security_group_ids" {
  description = "app-sg."
  type        = list(string)
}

# --- Container ------------------------------------------------------------

variable "image" {
  description = "Full arm64 image URI including the tag."
  type        = string
}

variable "cpu" {
  description = "Task CPU units (1024 = 1 vCPU)."
  type        = number
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
}

variable "container_port" {
  description = "Port the application listens on."
  type        = number
}

variable "command" {
  description = "Override the image command. Null keeps the image default."
  type        = list(string)
  default     = null
}

variable "environment" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Environment variables read from Secrets Manager at start: NAME => secret ARN, or ARN:json-key:: for one key."
  type        = map(string)
  default     = {}
}

variable "secrets_kms_key_arn" {
  description = "KMS key that encrypts the secrets."
  type        = string
}

variable "readonly_root_filesystem" {
  description = "Mount the root filesystem read-only. Turn on once the app writes only to mounted volumes."
  type        = bool
  default     = false
}

variable "stop_timeout" {
  description = "Seconds between SIGTERM and SIGKILL. 120 is the Fargate maximum and matches the Spot warning."
  type        = number
  default     = 120
}

# --- Load balancer --------------------------------------------------------

variable "listener_arn" {
  description = "HTTPS listener ARN."
  type        = string
}

variable "listener_rule_priority" {
  description = "Unique priority of this service's host-header rule."
  type        = number
}

variable "host_headers" {
  description = "Hostnames routed to this service."
  type        = list(string)
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix, for metrics and request-count scaling."
  type        = string
}

variable "health_check_path" {
  description = "Path the ALB health-checks."
  type        = string
  default     = "/healthz"
}

variable "health_check_grace_period" {
  description = "Seconds after start before failed health checks count."
  type        = number
  default     = 60
}

variable "deregistration_delay" {
  description = "Seconds a stopping task keeps draining before it is removed from the ALB."
  type        = number
  default     = 60
}

# --- Capacity and scaling -------------------------------------------------

variable "on_demand_base" {
  description = "Tasks that always run on regular Fargate. Every task above this runs on Fargate Spot."
  type        = number
  default     = 1
}

variable "min_tasks" {
  description = "Minimum running tasks."
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Maximum running tasks (the Spot cap is max_tasks - on_demand_base)."
  type        = number
}

variable "cpu_target" {
  description = "Target average CPU % for scaling."
  type        = number
  default     = 60
}

variable "requests_per_target" {
  description = "Target ALB requests per task per minute for scaling."
  type        = number
  default     = 1000
}

variable "scale_out_cooldown" {
  description = "Seconds between scale-out steps."
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Seconds between scale-in steps."
  type        = number
  default     = 300
}

# --- Logs, alarms, IAM ----------------------------------------------------

variable "log_retention_days" {
  description = "Application log retention."
  type        = number
  default     = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key for the application log group."
  type        = string
}

variable "exec_log_group_arn" {
  description = "Cluster log group that records ECS Exec sessions."
  type        = string
}

variable "exec_kms_key_arn" {
  description = "Key that encrypts ECS Exec sessions."
  type        = string
}

variable "alarm_topic_arn" {
  description = "SNS topic for alarms. Null creates the alarms without notifications."
  type        = string
  default     = null
}

variable "cpu_alarm_threshold" {
  description = "Alarm when average CPU stays above this % for 10 minutes."
  type        = number
  default     = 80
}

variable "task_policy_json" {
  description = "What the application itself may do in AWS (its S3 buckets and IoT topics). Null grants nothing beyond ECS Exec."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Permission boundary attached to both roles."
  type        = string
}

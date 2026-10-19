variable "admin_user_arns" {
  description = "IAM users (with MFA) who may assume hive-admin and run Terraform."
  type        = list(string)

  validation {
    condition     = length(var.admin_user_arns) > 0
    error_message = "At least one engineer must be able to assume hive-admin."
  }
}

variable "developer_user_arns" {
  description = "IAM users who may assume hive-developer."
  type        = list(string)
  default     = []
}

variable "readonly_user_arns" {
  description = "IAM users who may assume hive-readonly."
  type        = list(string)
  default     = []
}

variable "protected_resource_arns" {
  description = "ARNs of the running stack that no hive-* role may change: the old EKS cluster and node groups, Aurora cluster and instances, old load balancers, listeners and target groups, and the Alexa instance. Wildcards allowed."
  type        = list(string)

  validation {
    condition     = length(var.protected_resource_arns) > 0
    error_message = "List the running stack's resources so the permission boundary can protect them."
  }
}

variable "session_duration_seconds" {
  description = "How long an assumed session lasts."
  type        = number
  default     = 3600
}

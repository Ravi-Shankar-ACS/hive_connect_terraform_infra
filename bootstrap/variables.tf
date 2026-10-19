variable "account_id" {
  description = "The AWS account (the existing one). Terraform refuses to run against any other."
  type        = string
}

variable "region" {
  description = "Region of the state bucket."
  type        = string
  default     = "ap-south-1"
}

variable "break_glass_principal_arns" {
  description = "Existing administrators (IAM user or role ARNs) who keep access to the state bucket besides hive-admin. They apply bootstrap and the account stack."
  type        = list(string)

  validation {
    condition     = length(var.break_glass_principal_arns) > 0
    error_message = "List at least one administrator, or the state bucket would only be reachable by hive-admin."
  }
}

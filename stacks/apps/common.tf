# Variables every layer shares; their values live in envs/<env>/common.tfvars.

variable "account_id" {
  description = "The AWS account. Terraform refuses to run against any other."
  type        = string
}

variable "env" {
  description = "Environment name: uat or prod."
  type        = string

  validation {
    condition     = contains(["uat", "prod"], var.env)
    error_message = "env must be uat or prod."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

locals {
  name = "hive-${var.env}"
}

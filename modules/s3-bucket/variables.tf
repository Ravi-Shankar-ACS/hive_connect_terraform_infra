variable "name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for SSE-KMS. Leave null for SSE-S3, which ALB access logs require."
  type        = string
  default     = null
}

variable "expiration_days" {
  description = "Delete objects this many days after creation (log buckets). Null keeps objects."
  type        = number
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Delete overwritten or deleted object versions after this many days."
  type        = number
  default     = 90
}

variable "policy_json" {
  description = "Extra bucket policy statements (for example log delivery), merged with the TLS-only rule."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow Terraform to delete a bucket that still holds objects. Only for throwaway test stacks."
  type        = bool
  default     = false
}

variable "names" {
  description = "Repository names, for example [\"hive-uat/hiveconnect-api\", \"hive-uat/prism\"]."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the images."
  type        = string
}

variable "keep_last_images" {
  description = "Images kept per repository; older ones expire."
  type        = number
  default     = 20
}

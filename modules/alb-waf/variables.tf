variable "name" {
  description = "Name of the ALB and web ACL, for example hive-uat (32 characters at most)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets in two or more AZs."
  type        = list(string)
}

variable "security_group_id" {
  description = "alb-sg."
  type        = string
}

variable "zone_id" {
  description = "Existing Route 53 hosted zone that holds the hostnames."
  type        = string
}

variable "hostnames" {
  description = "Hostnames served by this ALB. All go on one ACM certificate and get alias records."
  type        = list(string)
}

variable "dns_weight" {
  description = "Null creates simple alias records. A number creates weighted records, used at production cutover to shift traffic from the old ALB."
  type        = number
  default     = null
}

variable "access_logs_bucket" {
  description = "S3 bucket (SSE-S3) for ALB access logs."
  type        = string
}

variable "waf_logs_bucket_arn" {
  description = "S3 bucket for WAF logs. Its name must start with aws-waf-logs-."
  type        = string
}

variable "waf_block_mode" {
  description = "False runs every WAF rule in Count mode (the first UAT week). True blocks."
  type        = bool
}

variable "waf_rate_limit" {
  description = "Requests per IP per 5 minutes before the rate rule acts."
  type        = number
  default     = 2000
}

variable "waf_count_only_rules" {
  description = "Rules in the core rule set that only count, even in Block mode. SizeRestrictions_BODY would otherwise block uploads over 8 KB (documents, firmware, images)."
  type        = list(string)
  default     = ["SizeRestrictions_BODY"]
}

variable "idle_timeout" {
  description = "Seconds an idle connection (including a WebSocket) stays open."
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Protect the ALB from deletion."
  type        = bool
  default     = true
}

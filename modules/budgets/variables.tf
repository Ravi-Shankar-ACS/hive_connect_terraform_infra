variable "name" {
  description = "Budget name prefix, for example hive-uat."
  type        = string
}

variable "amount_usd" {
  description = "Monthly limit in USD, before tax."
  type        = number
}

variable "tag_key" {
  description = "Cost-allocation tag that selects this environment's costs. It must be activated (account stack)."
  type        = string
  default     = "Env"
}

variable "tag_value" {
  description = "Value of that tag, for example uat."
  type        = string
}

variable "thresholds_percent" {
  description = "Actual-spend alerts as % of the limit."
  type        = list(number)
  default     = [80, 100, 120]
}

variable "sns_topic_arn" {
  description = "Alert topic."
  type        = string
}

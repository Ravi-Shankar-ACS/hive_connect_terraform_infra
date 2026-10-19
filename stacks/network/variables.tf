variable "vpc_cidr" {
  description = "VPC range (UAT 10.20.0.0/16, production 10.30.0.0/16)."
  type        = string
}

variable "azs" {
  description = "Availability Zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public tier, one per AZ."
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "App tier, one per AZ."
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "Data tier, one per AZ."
  type        = list(string)
}

variable "app_ports" {
  description = "Container ports of the services."
  type        = list(number)
}

variable "app_egress_tcp_ports" {
  description = "TCP ports tasks may open to the internet."
  type        = list(number)
  default     = [443]
}

variable "flow_log_retention_days" {
  description = "VPC flow log retention."
  type        = number
  default     = 14
}

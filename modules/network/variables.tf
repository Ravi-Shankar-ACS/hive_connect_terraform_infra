variable "name" {
  description = "Name prefix for every resource, for example hive-uat."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC range. Must not overlap 192.168.0.0/16 (EKS and Aurora) or 172.31.0.0/16 (default VPC)."
  type        = string
}

variable "azs" {
  description = "Availability Zones, one subnet per tier in each."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public tier (ALB, NAT gateway), one per AZ."
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "Private app tier (Fargate tasks), one per AZ."
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "Private data tier with no internet route (RDS), one per AZ."
  type        = list(string)
}

variable "app_ports" {
  description = "Container ports the ALB may reach in the app tier."
  type        = list(number)
}

variable "app_egress_tcp_ports" {
  description = "TCP ports the app tier may open to the internet through the NAT gateway."
  type        = list(number)
  default     = [443]
}

variable "db_port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "flow_log_retention_days" {
  description = "VPC flow log retention."
  type        = number
  default     = 14
}

variable "logs_kms_key_arn" {
  description = "KMS key that encrypts the flow log group."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary attached to every role this module creates."
  type        = string
}

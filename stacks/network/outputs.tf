output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets."
  value       = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  description = "App subnets."
  value       = module.network.app_subnet_ids
}

output "data_subnet_ids" {
  description = "Data subnets."
  value       = module.network.data_subnet_ids
}

output "alb_security_group_id" {
  description = "alb-sg."
  value       = module.network.alb_security_group_id
}

output "app_security_group_id" {
  description = "app-sg."
  value       = module.network.app_security_group_id
}

output "db_security_group_id" {
  description = "db-sg."
  value       = module.network.db_security_group_id
}

output "nat_gateway_id" {
  description = "NAT gateway ID."
  value       = module.network.nat_gateway_id
}

output "nat_public_ip" {
  description = "Give this address to every provider that filters by IP (Elasticsearch/APM, SMTP, WhatsApp)."
  value       = module.network.nat_public_ip
}

output "kms_key_arns" {
  description = "KMS key ARNs by purpose: rds, storage, app."
  value       = { for k, key in aws_kms_key.this : k => key.arn }
}

output "hostnames" {
  description = "Service => hostname."
  value       = { for k, s in var.services : k => s.hostname }
}

output "ecr_repository_urls" {
  description = "Service => ECR repository URL."
  value       = { for s in keys(var.services) : s => module.ecr.repository_urls["${local.name}/${s}"] }
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = module.edge.alb_dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix."
  value       = module.edge.alb_arn_suffix
}

output "https_listener_arn" {
  description = "HTTPS listener."
  value       = module.edge.https_listener_arn
}

output "web_acl_name" {
  description = "WAF web ACL."
  value       = module.edge.web_acl_name
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.cluster.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = module.cluster.arn
}

output "exec_log_group_arn" {
  description = "ECS Exec session log group."
  value       = module.cluster.exec_log_group_arn
}

output "app_bucket_names" {
  description = "Short name => bucket name."
  value       = { for k, b in module.app_buckets : k => b.id }
}

output "app_bucket_arns" {
  description = "Short name => bucket ARN."
  value       = { for k, b in module.app_buckets : k => b.arn }
}

output "secret_arns" {
  description = "Short name => secret ARN."
  value       = { for k, s in aws_secretsmanager_secret.app : k => s.arn }
}

output "alerts_topic_arn" {
  description = "SNS alert topic."
  value       = module.observability.alerts_topic_arn
}

output "iot_topic_prefix" {
  description = "IoT topic prefix of this environment."
  value       = var.iot_topic_prefix
}

output "iot_endpoint" {
  description = "MQTT (ATS) endpoint of the account's IoT Core."
  value       = var.iot_topic_prefix == null ? null : data.aws_iot_endpoint.this[0].endpoint_address
}

output "iot_device_policy_name" {
  description = "IoT policy for this environment's test devices."
  value       = var.iot_topic_prefix == null ? null : aws_iot_policy.devices[0].name
}

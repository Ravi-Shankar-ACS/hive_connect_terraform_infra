output "name" {
  description = "Cluster name."
  value       = aws_ecs_cluster.this.name
}

output "arn" {
  description = "Cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "exec_log_group_arn" {
  description = "Log group that records ECS Exec sessions; task roles need write access to it."
  value       = aws_cloudwatch_log_group.exec.arn
}

output "exec_kms_key_arn" {
  description = "Key that encrypts ECS Exec sessions; task roles need kms:Decrypt on it."
  value       = var.kms_key_arn
}

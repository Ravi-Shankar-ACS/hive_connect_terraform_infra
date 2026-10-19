output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "task_definition_family" {
  description = "Task definition family, for one-off tasks such as migrations."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "Current task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix, for dashboards."
  value       = aws_lb_target_group.this.arn_suffix
}

output "log_group_name" {
  description = "Application log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "task_role_arn" {
  description = "Role the application runs as."
  value       = aws_iam_role.task.arn
}

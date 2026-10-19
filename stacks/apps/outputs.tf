output "services" {
  description = "Per service: ECS service, task definition family, log group and URL."
  value = {
    for k, m in module.service : k => {
      service     = m.service_name
      task_family = m.task_definition_family
      log_group   = m.log_group_name
      url         = "https://${local.platform.hostnames[k]}"
    }
  }
}

output "db_admin_task_family" {
  description = "Run with: scripts/run-task.sh <env> db-admin"
  value       = aws_ecs_task_definition.db_admin.family
}

output "dashboard_url" {
  description = "CloudWatch dashboard."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.this.dashboard_name}"
}

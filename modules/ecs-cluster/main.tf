# Fargate-only cluster with both capacity providers. Services choose their own
# strategy (one on-demand task, Spot above it). The cluster default is plain
# FARGATE, so one-off tasks such as migrations never land on Spot.

resource "aws_cloudwatch_log_group" "exec" {
  name              = "/${var.name}/ecs/exec-sessions"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  # Every ECS Exec session (the replacement for SSH) is encrypted with the
  # environment's key and recorded.
  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
        cloud_watch_encryption_enabled = true
      }
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

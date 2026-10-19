# One ECS service on Fargate (Graviton): its task definition, target group,
# host-header rule, autoscaling and alarms.
#
# Capacity: the first `on_demand_base` tasks run on FARGATE; every task that
# autoscaling adds above them runs on FARGATE_SPOT (about 69% cheaper, may be
# reclaimed with two minutes' notice).

data "aws_region" "current" {}

locals {
  full_name     = "${var.name_prefix}-${var.name}"
  alarm_actions = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]

  # "arn:aws:secretsmanager:<region>:<account>:secret:<name>[:json-key::]" -> secret ARN
  secret_arns = distinct([for v in values(var.secrets) : join(":", slice(split(":", v), 0, 7))])

  container = merge(
    {
      name                   = var.name
      image                  = var.image
      essential              = true
      portMappings           = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment            = [for k, v in var.environment : { name = k, value = v }]
      secrets                = [for k, v in var.secrets : { name = k, valueFrom = v }]
      stopTimeout            = var.stop_timeout
      readonlyRootFilesystem = var.readonly_root_filesystem
      linuxParameters        = { initProcessEnabled = true }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "app"
          mode                  = "non-blocking"
          max-buffer-size       = "25m"
        }
      }
    },
    var.command == null ? {} : { command = var.command },
  )
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/${var.name_prefix}/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([local.container])
}

resource "aws_lb_target_group" "this" {
  name                 = local.full_name
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    host_header {
      values = var.host_headers
    }
  }
}

resource "aws_ecs_service" "this" {
  name             = var.name
  cluster          = var.cluster_arn
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = var.min_tasks
  platform_version = "LATEST"

  enable_execute_command            = true
  enable_ecs_managed_tags           = true
  propagate_tags                    = "SERVICE"
  health_check_grace_period_seconds = var.health_check_grace_period

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # A deployment that cannot get healthy rolls back to the previous task definition.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = var.on_demand_base
    weight            = 0
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }

  # Autoscaling owns the running count after the first apply.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener_rule.this]
}

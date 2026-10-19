# db-admin: a task definition (not a service) for reaching the private database
# without a bastion or an open port. scripts/run-task.sh starts it on regular
# Fargate and opens psql inside it with ECS Exec, signed in as the RDS master
# user. Use it to create the application roles, run checks after a restore
# drill, and inspect data. It stops by itself after an hour.

data "aws_caller_identity" "current" {}

locals {
  db_admin_name = "${local.name}-db-admin"
}

data "aws_iam_policy_document" "db_admin_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_group" "db_admin" {
  name              = "/${local.name}/ecs/db-admin"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.network.kms_key_arns.app
}

resource "aws_iam_role" "db_admin_execution" {
  name                 = "${local.db_admin_name}-exec"
  assume_role_policy   = data.aws_iam_policy_document.db_admin_assume.json
  permissions_boundary = local.boundary_arn
}

resource "aws_iam_role_policy_attachment" "db_admin_execution" {
  role       = aws_iam_role.db_admin_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "db_admin_execution" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.db.db_master_secret_arn]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [local.network.kms_key_arns.app]
  }
}

resource "aws_iam_role_policy" "db_admin_execution" {
  name   = "read-master-secret"
  role   = aws_iam_role.db_admin_execution.id
  policy = data.aws_iam_policy_document.db_admin_execution.json
}

resource "aws_iam_role" "db_admin_task" {
  name                 = "${local.db_admin_name}-task"
  assume_role_policy   = data.aws_iam_policy_document.db_admin_assume.json
  permissions_boundary = local.boundary_arn
}

data "aws_iam_policy_document" "db_admin_task" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.platform.exec_log_group_arn}:*"]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [local.network.kms_key_arns.app]
  }

  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "db_admin_task" {
  name   = "ecs-exec"
  role   = aws_iam_role.db_admin_task.id
  policy = data.aws_iam_policy_document.db_admin_task.json
}

resource "aws_ecs_task_definition" "db_admin" {
  family                   = local.db_admin_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.db_admin_execution.arn
  task_role_arn            = aws_iam_role.db_admin_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "db-admin"
    image     = var.db_admin_image
    essential = true
    command   = ["sleep", "3600"]

    environment = [
      { name = "PGHOST", value = local.db.db_address },
      { name = "PGPORT", value = tostring(local.db.db_port) },
      { name = "PGDATABASE", value = local.db.db_name },
      { name = "PGSSLMODE", value = "require" },
    ]

    secrets = [
      { name = "PGUSER", valueFrom = "${local.db.db_master_secret_arn}:username::" },
      { name = "PGPASSWORD", valueFrom = "${local.db.db_master_secret_arn}:password::" },
    ]

    linuxParameters = { initProcessEnabled = true }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.db_admin.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "db-admin"
      }
    }
  }])
}

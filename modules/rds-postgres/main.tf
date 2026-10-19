# RDS PostgreSQL in the data subnets: private, KMS-encrypted, TLS enforced,
# master password generated and held by RDS in Secrets Manager.
#
# Limits to keep in mind (plan section 5):
# - gp3 below 400 GiB is fixed at 3,000 IOPS and 125 MiB/s.
# - db.t4g CPU above its 20% baseline is billed as surplus credits
#   ($0.075 per vCPU-hour); the observability module alarms on it.

data "aws_partition" "current" {}

locals {
  family = "postgres${split(".", var.engine_version)[0]}"

  # rds.force_ssl is set on its own below so it can never be overridden.
  parameters = merge(
    {
      "log_connections"            = "1"
      "log_disconnections"         = "1"
      "log_min_duration_statement" = "1000" # log statements slower than 1 s
    },
    var.parameters,
  )
}

resource "aws_db_subnet_group" "this" {
  name       = var.identifier
  subnet_ids = var.subnet_ids

  tags = { Name = var.identifier }
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.identifier}-${local.family}-"
  family      = local.family
  description = "${var.identifier} parameters"

  # TLS is mandatory for every connection.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  dynamic "parameter" {
    for_each = { for k, v in local.parameters : k => v if k != "rds.force_ssl" }
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Created up front so the exported logs get a retention period and encryption.
resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(["postgresql", "upgrade"])

  name              = "/aws/rds/instance/${var.identifier}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name                 = "${var.identifier}-monitoring"
  assume_role_policy   = data.aws_iam_policy_document.monitoring_assume.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  port           = 5432
  multi_az       = var.multi_az

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name                       = var.db_name
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.master_secret_kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false
  network_type           = "IPV4"
  parameter_group_name   = aws_db_parameter_group.this.name
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  backup_retention_period   = var.backup_retention_days
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = var.apply_immediately

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = var.kms_key_arn
  database_insights_mode                = "standard"

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn

  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  iam_database_authentication_enabled = false

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy_attachment.monitoring]
}

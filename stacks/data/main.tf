# Layer 2 of 4: the PostgreSQL database in the data subnets.

data "aws_partition" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "hive-tfstate-${var.account_id}"
    key    = "${var.env}/network.tfstate"
    region = var.region
  }
}

locals {
  network = data.terraform_remote_state.network.outputs
}

module "postgres" {
  source = "../../modules/rds-postgres"

  identifier            = "${local.name}-postgres"
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  multi_az              = var.multi_az
  db_name               = var.db_name
  master_username       = var.master_username

  subnet_ids         = local.network.data_subnet_ids
  security_group_ids = [local.network.db_security_group_id]

  kms_key_arn               = local.network.kms_key_arns.rds
  master_secret_kms_key_arn = local.network.kms_key_arns.app
  logs_kms_key_arn          = local.network.kms_key_arns.app

  backup_retention_days = var.backup_retention_days
  deletion_protection   = var.deletion_protection
  apply_immediately     = var.apply_immediately
  log_retention_days    = var.log_retention_days

  permissions_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:policy/hive-boundary"
}

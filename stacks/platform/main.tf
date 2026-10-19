# Layer 3 of 4: everything the services run on - edge (Route 53, ACM, ALB, WAF),
# ECR, the ECS cluster, S3 buckets, secrets, alarms and the budget.

data "aws_partition" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "hive-tfstate-${var.account_id}"
    key    = "${var.env}/network.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = "hive-tfstate-${var.account_id}"
    key    = "${var.env}/data.tfstate"
    region = var.region
  }
}

data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

locals {
  network = data.terraform_remote_state.network.outputs
  db      = data.terraform_remote_state.data.outputs
  s3_arn  = "arn:${data.aws_partition.current.partition}:s3:::"
}

# --- Images ---------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  names       = [for s in keys(var.services) : "${local.name}/${s}"]
  kms_key_arn = local.network.kms_key_arns.storage
}

# --- Edge ------------------------------------------------------------------

module "edge" {
  source = "../../modules/alb-waf"

  name                = local.name
  public_subnet_ids   = local.network.public_subnet_ids
  security_group_id   = local.network.alb_security_group_id
  zone_id             = data.aws_route53_zone.this.zone_id
  hostnames           = [for s in values(var.services) : s.hostname]
  dns_weight          = var.dns_weight
  access_logs_bucket  = module.alb_logs_bucket.id
  waf_logs_bucket_arn = module.waf_logs_bucket.arn
  waf_block_mode      = var.waf_block_mode
  waf_rate_limit      = var.waf_rate_limit
  idle_timeout        = var.alb_idle_timeout
  deletion_protection = var.alb_deletion_protection
}

# --- Compute ---------------------------------------------------------------

module "cluster" {
  source = "../../modules/ecs-cluster"

  name               = local.name
  kms_key_arn        = local.network.kms_key_arns.app
  log_retention_days = var.log_retention_days
}

# --- Secrets (created empty; values are set by hand) -----------------------

resource "aws_secretsmanager_secret" "app" {
  #checkov:skip=CKV2_AWS_57:Third-party credentials (SMTP, WhatsApp, OAuth...) cannot rotate automatically; they are rotated by hand.
  for_each = var.secrets

  name                    = "${local.name}/${each.key}"
  description             = each.value
  kms_key_id              = local.network.kms_key_arns.app
  recovery_window_in_days = var.secret_recovery_days
}

# --- Alarms and budget -----------------------------------------------------

module "observability" {
  source = "../../modules/observability"

  name                    = local.name
  alert_emails            = var.alert_emails
  kms_key_arn             = local.network.kms_key_arns.app
  alb_arn_suffix          = module.edge.alb_arn_suffix
  nat_gateway_id          = local.network.nat_gateway_id
  db_instance_identifier  = local.db.db_identifier
  db_allocated_storage_gb = local.db.db_allocated_storage
  cluster_arn             = module.cluster.arn
}

module "budget" {
  source = "../../modules/budgets"

  name          = local.name
  amount_usd    = var.monthly_budget_usd
  tag_key       = "Env"
  tag_value     = var.env
  sns_topic_arn = module.observability.alerts_topic_arn
}

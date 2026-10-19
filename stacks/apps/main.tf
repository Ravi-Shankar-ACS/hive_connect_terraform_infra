# Layer 4 of 4: the HiveConnect and Prism services. Deploying a new version
# means changing image_tag in envs/<env>/apps.tfvars and applying this layer.

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

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = "hive-tfstate-${var.account_id}"
    key    = "${var.env}/platform.tfstate"
    region = var.region
  }
}

locals {
  network  = data.terraform_remote_state.network.outputs
  db       = data.terraform_remote_state.data.outputs
  platform = data.terraform_remote_state.platform.outputs

  boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:policy/hive-boundary"

  # "smtp:password" -> "arn:...:secret:hive-uat/smtp-AbC123:password::"
  # "smtp"          -> "arn:...:secret:hive-uat/smtp-AbC123" (whole secret string)
  secret_refs = {
    for svc, cfg in var.services : svc => {
      for env_name, ref in cfg.secrets : env_name => (
        length(split(":", ref)) == 1
        ? local.platform.secret_arns[ref]
        : "${local.platform.secret_arns[split(":", ref)[0]]}:${split(":", ref)[1]}::"
      )
    }
  }
}

module "service" {
  source   = "../../modules/ecs-service"
  for_each = var.services

  name         = each.key
  name_prefix  = local.name
  cluster_name = local.platform.cluster_name
  cluster_arn  = local.platform.cluster_arn

  vpc_id             = local.network.vpc_id
  subnet_ids         = local.network.app_subnet_ids
  security_group_ids = [local.network.app_security_group_id]

  image          = "${local.platform.ecr_repository_urls[each.key]}:${each.value.image_tag}"
  cpu            = each.value.cpu
  memory         = each.value.memory
  container_port = each.value.port
  command        = each.value.command
  environment    = each.value.environment
  secrets        = local.secret_refs[each.key]

  secrets_kms_key_arn = local.network.kms_key_arns.app
  logs_kms_key_arn    = local.network.kms_key_arns.app
  log_retention_days  = var.log_retention_days
  exec_log_group_arn  = local.platform.exec_log_group_arn
  exec_kms_key_arn    = local.network.kms_key_arns.app

  listener_arn           = local.platform.https_listener_arn
  listener_rule_priority = each.value.listener_priority
  host_headers           = [local.platform.hostnames[each.key]]
  alb_arn_suffix         = local.platform.alb_arn_suffix
  health_check_path      = each.value.health_check_path

  on_demand_base      = each.value.on_demand_base
  min_tasks           = each.value.min_tasks
  max_tasks           = each.value.max_tasks
  cpu_target          = each.value.cpu_target
  requests_per_target = each.value.requests_per_target

  alarm_topic_arn          = local.platform.alerts_topic_arn
  task_policy_json         = try(data.aws_iam_policy_document.task[each.key].json, null)
  permissions_boundary_arn = local.boundary_arn
}

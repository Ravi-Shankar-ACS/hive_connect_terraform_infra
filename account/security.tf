# Security baseline. Each piece has a switch because the account is shared:
# run scripts/preflight.sh first and set to false anything already turned on.

locals {
  config_bucket     = "hive-account-config-${var.account_id}"
  cloudtrail_bucket = "hive-account-cloudtrail-${var.account_id}"
  trail_arn         = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.region}:${var.account_id}:trail/hive-account-trail"
}

# --- GuardDuty ------------------------------------------------------------

resource "aws_guardduty_detector" "this" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector_feature" "this" {
  for_each = var.enable_guardduty ? var.guardduty_features : {}

  detector_id = aws_guardduty_detector.this[0].id
  name        = each.key
  status      = each.value
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  count = var.enable_guardduty ? 1 : 0

  name        = "hive-account-guardduty-findings"
  description = "GuardDuty findings of medium severity or higher."

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail      = { severity = [{ numeric = [">=", 4] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty" {
  count = var.enable_guardduty ? 1 : 0

  rule = aws_cloudwatch_event_rule.guardduty[0].name
  arn  = aws_sns_topic.account_alerts.arn

  input_transformer {
    input_paths = {
      severity = "$.detail.severity"
      type     = "$.detail.type"
      title    = "$.detail.title"
    }
    input_template = "\"GuardDuty (severity <severity>) <type>: <title>\""
  }
}

# --- AWS Config (limited to the resource types this build uses) -----------

module "config_bucket" {
  count  = var.enable_config ? 1 : 0
  source = "../modules/s3-bucket"

  name            = local.config_bucket
  expiration_days = 365
  policy_json     = data.aws_iam_policy_document.config_bucket.json
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid       = "ConfigAclCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.config_bucket}"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }

  statement {
    sid       = "ConfigDelivery"
    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.config_bucket}/AWSLogs/${var.account_id}/Config/*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0

  name               = "hive-account-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}

resource "aws_iam_role_policy_attachment" "config" {
  count = var.enable_config ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_delivery" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.config_bucket}/AWSLogs/${var.account_id}/Config/*"]
  }

  statement {
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.config_bucket}"]
  }
}

resource "aws_iam_role_policy" "config_delivery" {
  count = var.enable_config ? 1 : 0

  name   = "deliver-to-bucket"
  role   = aws_iam_role.config[0].id
  policy = data.aws_iam_policy_document.config_delivery.json
}

resource "aws_config_configuration_recorder" "this" {
  count = var.enable_config ? 1 : 0

  name     = "hive-account"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = var.config_resource_types

    recording_strategy {
      use_only = "INCLUSION_BY_RESOURCE_TYPES"
    }
  }

  # Daily snapshots instead of every change keep Config near its $5 estimate.
  recording_mode {
    recording_frequency = "DAILY"
  }
}

resource "aws_config_delivery_channel" "this" {
  count = var.enable_config ? 1 : 0

  name           = "hive-account"
  s3_bucket_name = module.config_bucket[0].id

  depends_on = [aws_config_configuration_recorder.this, aws_iam_role_policy.config_delivery]
}

resource "aws_config_configuration_recorder_status" "this" {
  count = var.enable_config ? 1 : 0

  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

# --- IAM Access Analyzer --------------------------------------------------

resource "aws_accessanalyzer_analyzer" "this" {
  count = var.enable_access_analyzer ? 1 : 0

  analyzer_name = "hive-account"
  type          = "ACCOUNT"
}

# --- CloudTrail (management events are free for the first trail) ---------

module "cloudtrail_bucket" {
  count  = var.enable_cloudtrail ? 1 : 0
  source = "../modules/s3-bucket"

  name            = local.cloudtrail_bucket
  expiration_days = 365
  policy_json     = data.aws_iam_policy_document.cloudtrail_bucket.json
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_bucket}"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_bucket}/AWSLogs/${var.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_cloudtrail" "this" {
  #checkov:skip=CKV_AWS_35:The trail bucket is private, versioned and SSE-S3 encrypted; a dedicated CMK is not in the plan.
  #checkov:skip=CKV_AWS_252:Findings are alerted through GuardDuty; per-file SNS notifications are not needed.
  #checkov:skip=CKV2_AWS_10:CloudWatch Logs delivery would add ingestion cost; the trail is queried from S3.
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "hive-account-trail"
  s3_bucket_name                = module.cloudtrail_bucket[0].id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
}

# --- Inspector: scan hive images on push ---------------------------------

resource "aws_inspector2_enabler" "ecr" {
  count = var.enable_inspector_ecr ? 1 : 0

  account_ids    = [var.account_id]
  resource_types = ["ECR"]
}

resource "aws_ecr_registry_scanning_configuration" "this" {
  count = var.enable_inspector_ecr ? 1 : 0

  scan_type = "ENHANCED"

  dynamic "rule" {
    for_each = var.inspector_ecr_repository_filters
    content {
      scan_frequency = "SCAN_ON_PUSH"

      repository_filter {
        filter      = rule.value
        filter_type = "WILDCARD"
      }
    }
  }

  depends_on = [aws_inspector2_enabler.ecr]
}

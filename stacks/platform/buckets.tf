# Application buckets (certificates, documents, firmware, images...) plus the
# two log buckets. Every bucket is private, versioned and TLS-only.

data "aws_elb_service_account" "this" {}

module "app_buckets" {
  source   = "../../modules/s3-bucket"
  for_each = toset(var.app_buckets)

  name        = "${local.name}-${each.key}-${var.account_id}"
  kms_key_arn = local.network.kms_key_arns.storage
}

# --- ALB access logs (ALB can only write to SSE-S3 buckets) ----------------

locals {
  alb_logs_bucket = "${local.name}-alb-logs-${var.account_id}"
  waf_logs_bucket = "aws-waf-logs-${local.name}-${var.account_id}"
}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "AlbAccessLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${local.s3_arn}${local.alb_logs_bucket}/alb/AWSLogs/${var.account_id}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }
}

module "alb_logs_bucket" {
  #checkov:skip=CKV_AWS_145:ALB access logs only support SSE-S3.
  source = "../../modules/s3-bucket"

  name                               = local.alb_logs_bucket
  expiration_days                    = 30
  noncurrent_version_expiration_days = 1
  policy_json                        = data.aws_iam_policy_document.alb_logs.json
}

# --- WAF logs (bucket name must start with aws-waf-logs-) ------------------

data "aws_iam_policy_document" "waf_logs" {
  statement {
    sid       = "WafLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${local.s3_arn}${local.waf_logs_bucket}/AWSLogs/${var.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "WafLogDeliveryAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = ["${local.s3_arn}${local.waf_logs_bucket}"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

module "waf_logs_bucket" {
  source = "../../modules/s3-bucket"

  name                               = local.waf_logs_bucket
  kms_key_arn                        = local.network.kms_key_arns.storage
  expiration_days                    = 30
  noncurrent_version_expiration_days = 1
  policy_json                        = data.aws_iam_policy_document.waf_logs.json
}

# Three customer-managed keys for the environment ($1 a month each):
#   rds     - database storage, snapshots and Performance Insights
#   storage - S3 buckets, ECR images and WAF logs
#   app     - Secrets Manager, CloudWatch log groups and the SNS alert topic

locals {
  kms_keys = {
    rds     = "RDS storage, snapshots and Performance Insights"
    storage = "S3 buckets, ECR images and WAF logs"
    app     = "Secrets Manager, CloudWatch Logs and SNS alerts"
  }
  account_root = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:root"
}

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Standard key administration statement for the account root; IAM policies decide who may use the key.
  #checkov:skip=CKV_AWS_111:Standard key administration statement for the account root; IAM policies decide who may use the key.
  #checkov:skip=CKV_AWS_356:In a key policy, "*" means this key only.
  for_each = local.kms_keys

  statement {
    sid       = "AccountAdministersTheKey"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  dynamic "statement" {
    for_each = each.key == "app" ? [1] : []
    content {
      sid       = "CloudWatchLogsEncryptLogGroups"
      actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["logs.${var.region}.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${var.account_id}:log-group:*"]
      }
    }
  }

  dynamic "statement" {
    for_each = each.key == "app" ? [1] : []
    content {
      sid       = "AlarmEventAndBudgetPublishersUseTheSnsTopic"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com", "budgets.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = each.key == "storage" ? [1] : []
    content {
      sid       = "WafLogDelivery"
      actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
      resources = ["*"]

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
}

resource "aws_kms_key" "this" {
  for_each = local.kms_keys

  description             = "${local.name} ${each.key}: ${each.value}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms[each.key].json
}

resource "aws_kms_alias" "this" {
  for_each = local.kms_keys

  name          = "alias/${local.name}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}

# Account-wide pieces shared by UAT and production. Applied by the break-glass
# administrator, not by hive-admin: the permission boundary deliberately stops
# hive-* roles from editing their own guardrails or the security baseline.

data "aws_partition" "current" {}

module "iam_roles" {
  source = "../modules/iam-roles"

  admin_user_arns         = var.admin_user_arns
  developer_user_arns     = var.developer_user_arns
  readonly_user_arns      = var.readonly_user_arns
  protected_resource_arns = var.protected_resource_arns
}

# Account-level alerts (GuardDuty findings). Each environment has its own
# encrypted topic for its alarms.
resource "aws_sns_topic" "account_alerts" {
  #checkov:skip=CKV_AWS_26:Carries GuardDuty finding summaries only; EventBridge cannot publish to the AWS-managed SNS key, and a dedicated CMK is not worth it here.
  name = "hive-account-alerts"
}

data "aws_iam_policy_document" "account_alerts" {
  statement {
    sid       = "AccountOwner"
    actions   = ["sns:*"]
    resources = [aws_sns_topic.account_alerts.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.account_id}:root"]
    }
  }

  statement {
    sid       = "EventBridgePublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.account_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "account_alerts" {
  arn    = aws_sns_topic.account_alerts.arn
  policy = data.aws_iam_policy_document.account_alerts.json
}

resource "aws_sns_topic_subscription" "account_alerts" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.account_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

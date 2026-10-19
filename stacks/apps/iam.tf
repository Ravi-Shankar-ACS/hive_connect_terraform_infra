# What each application may do in AWS, through its task role. Only the buckets
# listed for the service in apps.tfvars, and only this environment's IoT topics.
#
# If an application also provisions devices (creates things and certificates,
# attaches the device policy), add those IoT actions here once they are known.

locals {
  iot_arn = "arn:${data.aws_partition.current.partition}:iot:${var.region}:${var.account_id}"
}

data "aws_iam_policy_document" "task" {
  for_each = { for k, v in var.services : k => v if length(v.s3_buckets) > 0 || v.iot }

  dynamic "statement" {
    for_each = length(each.value.s3_buckets) > 0 ? [1] : []
    content {
      sid       = "ListOwnBuckets"
      actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
      resources = [for b in each.value.s3_buckets : local.platform.app_bucket_arns[b]]
    }
  }

  dynamic "statement" {
    for_each = length(each.value.s3_buckets) > 0 ? [1] : []
    content {
      sid       = "ReadWriteOwnObjects"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
      resources = [for b in each.value.s3_buckets : "${local.platform.app_bucket_arns[b]}/*"]
    }
  }

  dynamic "statement" {
    for_each = length(each.value.s3_buckets) > 0 ? [1] : []
    content {
      sid       = "UseTheBucketKey"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [local.network.kms_key_arns.storage]
    }
  }

  dynamic "statement" {
    for_each = each.value.iot ? [1] : []
    content {
      sid       = "IotConnect"
      actions   = ["iot:Connect"]
      resources = ["${local.iot_arn}:client/${local.name}-${each.key}-*"]
    }
  }

  dynamic "statement" {
    for_each = each.value.iot ? [1] : []
    content {
      sid       = "IotOwnTopics"
      actions   = ["iot:Publish", "iot:Receive", "iot:RetainPublish"]
      resources = ["${local.iot_arn}:topic/${local.platform.iot_topic_prefix}/*"]
    }
  }

  dynamic "statement" {
    for_each = each.value.iot ? [1] : []
    content {
      sid       = "IotOwnTopicFilters"
      actions   = ["iot:Subscribe"]
      resources = ["${local.iot_arn}:topicfilter/${local.platform.iot_topic_prefix}/*"]
    }
  }

  dynamic "statement" {
    for_each = each.value.iot ? [1] : []
    content {
      sid       = "IotEndpoint"
      actions   = ["iot:DescribeEndpoint"]
      resources = ["*"]
    }
  }
}

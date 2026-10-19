# UAT uses the IoT Core already in this account, kept apart by its own topic
# prefix. This is the policy attached to UAT's test devices (set it as
# AWS_IOT_POLICY_NAME): a device may connect only as its own thing, and only
# publish and subscribe under <prefix>/<its thing name>/.
#
# Check the topic layout against the firmware before the first device test
# (plan open question 1) and adjust the resources below if it differs.

data "aws_iot_endpoint" "this" {
  count = var.iot_topic_prefix == null ? 0 : 1

  endpoint_type = "iot:Data-ATS"
}

locals {
  iot_arn = "arn:${data.aws_partition.current.partition}:iot:${var.region}:${var.account_id}"
}

data "aws_iam_policy_document" "iot_devices" {
  count = var.iot_topic_prefix == null ? 0 : 1

  statement {
    sid       = "ConnectAsOwnThing"
    actions   = ["iot:Connect"]
    resources = ["${local.iot_arn}:client/$${iot:Connection.Thing.ThingName}"]

    condition {
      test     = "Bool"
      variable = "iot:Connection.Thing.IsAttached"
      values   = ["true"]
    }
  }

  statement {
    sid       = "PublishAndReceiveOwnTopics"
    actions   = ["iot:Publish", "iot:Receive"]
    resources = ["${local.iot_arn}:topic/${var.iot_topic_prefix}/$${iot:Connection.Thing.ThingName}/*"]
  }

  statement {
    sid       = "SubscribeOwnTopics"
    actions   = ["iot:Subscribe"]
    resources = ["${local.iot_arn}:topicfilter/${var.iot_topic_prefix}/$${iot:Connection.Thing.ThingName}/*"]
  }
}

resource "aws_iot_policy" "devices" {
  count = var.iot_topic_prefix == null ? 0 : 1

  name   = "${local.name}-devices"
  policy = data.aws_iam_policy_document.iot_devices[0].json
}

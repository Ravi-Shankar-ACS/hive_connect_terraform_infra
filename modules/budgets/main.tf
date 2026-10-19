# Monthly cost budget for one environment, filtered by its cost-allocation tag,
# alerting on actual spend at each threshold and on a forecast above 100%.

resource "aws_budgets_budget" "this" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.amount_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:%s$%s", var.tag_key, var.tag_value)]
  }

  dynamic "notification" {
    for_each = toset(var.thresholds_percent)
    content {
      notification_type         = "ACTUAL"
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      subscriber_sns_topic_arns = [var.sns_topic_arn]
    }
  }

  notification {
    notification_type         = "FORECASTED"
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    subscriber_sns_topic_arns = [var.sns_topic_arn]
  }
}

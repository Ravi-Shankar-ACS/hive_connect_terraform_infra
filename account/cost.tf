# Cost-allocation tags let budgets and Cost Explorer separate the new stack from
# the old one. AWS only offers a tag for activation after it has seen it on a
# resource, so leave activate_cost_tags = false until a day after the first
# environment layer is applied, then set it to true and apply again.

resource "aws_ce_cost_allocation_tag" "this" {
  for_each = var.activate_cost_tags ? toset(["Project", "Env"]) : toset([])

  tag_key = each.key
  status  = "Active"
}

resource "aws_ce_anomaly_monitor" "this" {
  count = var.activate_cost_tags ? 1 : 0

  name         = "hive-project"
  monitor_type = "CUSTOM"
  monitor_specification = jsonencode({
    Tags = {
      Key          = "Project"
      Values       = ["HiveConnect"]
      MatchOptions = ["EQUALS"]
    }
  })

  depends_on = [aws_ce_cost_allocation_tag.this]
}

resource "aws_ce_anomaly_subscription" "this" {
  count = var.activate_cost_tags ? 1 : 0

  name             = "hive-project-daily"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.this[0].arn]

  dynamic "subscriber" {
    for_each = var.alert_emails
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}

# Events that matter but are not metrics:
# - ECS: a task that cannot be placed (for example no Spot capacity), tasks that
#   keep failing to start, and failed deployments.
# - RDS: instance failures, low storage, and any failed backup.

resource "aws_cloudwatch_event_rule" "ecs" {
  name        = "${var.name}-ecs-problems"
  description = "ECS service warnings and errors, including Spot tasks that could not be placed."

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Service Action", "ECS Deployment State Change"]
    detail = {
      clusterArn = [var.cluster_arn]
      eventType  = ["WARN", "ERROR"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecs" {
  rule = aws_cloudwatch_event_rule.ecs.name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      type    = "$.detail-type"
      event   = "$.detail.eventName"
      reason  = "$.detail.reason"
      service = "$.resources[0]"
    }
    input_template = "\"${var.name} ECS <type>: <event> on <service>. <reason>\""
  }
}

resource "aws_cloudwatch_event_rule" "rds" {
  name        = "${var.name}-rds-problems"
  description = "RDS failures, low storage and failed backups for ${var.db_instance_identifier}."

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Instance Event", "RDS DB Snapshot Event"]
    detail = {
      SourceIdentifier = [{ prefix = var.db_instance_identifier }, { prefix = "rds:${var.db_instance_identifier}" }]
      "$or" = [
        { EventCategories = ["failure", "low storage"] },
        { Message = [{ wildcard = "*fail*" }, { wildcard = "*Fail*" }] },
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "rds" {
  rule = aws_cloudwatch_event_rule.rds.name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      source  = "$.detail.SourceIdentifier"
      message = "$.detail.Message"
    }
    input_template = "\"${var.name} RDS <source>: <message>\""
  }
}

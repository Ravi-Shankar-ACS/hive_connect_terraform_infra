# Environment-wide alarms (per-service alarms live in the ecs-service module).

locals {
  actions = [aws_sns_topic.alerts.arn]
}

# --- ALB -----------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx" {
  alarm_name          = "${var.name}-alb-5xx"
  alarm_description   = "The ALB itself returned more than ${var.alb_5xx_threshold} 5xx responses in 5 minutes (no healthy target, timeouts)."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alb_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "${var.name}-app-5xx"
  alarm_description   = "The applications returned more than ${var.alb_5xx_threshold} 5xx responses in 5 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alb_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# --- NAT gateway ----------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "nat_port_allocation" {
  alarm_name          = "${var.name}-nat-port-allocation-errors"
  alarm_description   = "The NAT gateway ran out of source ports; outbound calls are failing."
  namespace           = "AWS/NATGateway"
  metric_name         = "ErrorPortAllocation"
  dimensions          = { NatGatewayId = var.nat_gateway_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# --- RDS -------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name}-db-cpu-high"
  alarm_description   = "Database CPU above 80% for 10 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_credit_balance" {
  alarm_name          = "${var.name}-db-cpu-credits-low"
  alarm_description   = "Database CPU credit balance below ${var.db_cpu_credit_balance_threshold}; surplus credits will be charged soon."
  namespace           = "AWS/RDS"
  metric_name         = "CPUCreditBalance"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.db_cpu_credit_balance_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_surplus_credits" {
  alarm_name          = "${var.name}-db-surplus-credits-charged"
  alarm_description   = "The database is being billed for surplus CPU credits ($0.075 per vCPU-hour)."
  namespace           = "AWS/RDS"
  metric_name         = "CPUSurplusCreditsCharged"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_free_storage" {
  alarm_name          = "${var.name}-db-free-storage-low"
  alarm_description   = "Database free storage below 20% of ${var.db_allocated_storage_gb} GB."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.db_allocated_storage_gb * 0.2 * 1024 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.name}-db-connections-high"
  alarm_description   = "More than ${var.db_connections_threshold} database connections; check pool size x task count."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.db_connections_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_iops" {
  alarm_name          = "${var.name}-db-iops-near-limit"
  alarm_description   = "Database read + write IOPS above ${var.db_iops_threshold} for 10 minutes (gp3 ceiling 3,000)."
  evaluation_periods  = 10
  threshold           = var.db_iops_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "iops"
    expression  = "read + write"
    label       = "Total IOPS"
    return_data = true
  }

  metric_query {
    id = "read"
    metric {
      namespace   = "AWS/RDS"
      metric_name = "ReadIOPS"
      dimensions  = { DBInstanceIdentifier = var.db_instance_identifier }
      stat        = "Average"
      period      = 60
    }
  }

  metric_query {
    id = "write"
    metric {
      namespace   = "AWS/RDS"
      metric_name = "WriteIOPS"
      dimensions  = { DBInstanceIdentifier = var.db_instance_identifier }
      stat        = "Average"
      period      = 60
    }
  }
}

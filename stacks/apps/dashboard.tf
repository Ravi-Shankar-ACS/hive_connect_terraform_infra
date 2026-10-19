# One CloudWatch dashboard for the environment: traffic, each service, the
# database and the NAT gateway.

locals {
  alb   = local.platform.alb_arn_suffix
  db_id = local.db.db_identifier

  service_widgets = flatten([
    for name, svc in module.service : [
      {
        title = "${name}: CPU and memory (%)"
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ClusterName", local.platform.cluster_name, "ServiceName", svc.service_name],
          ["AWS/ECS", "MemoryUtilization", "ClusterName", local.platform.cluster_name, "ServiceName", svc.service_name],
        ]
        stat = "Average"
      },
      {
        title = "${name}: healthy and unhealthy tasks"
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", svc.target_group_arn_suffix, "LoadBalancer", local.alb],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", svc.target_group_arn_suffix, "LoadBalancer", local.alb],
        ]
        stat = "Maximum"
      },
    ]
  ])

  widgets = concat(
    [
      {
        title = "ALB requests and errors"
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb],
          ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", local.alb],
        ]
        stat = "Sum"
      },
      {
        title   = "ALB response time p95 (s)"
        metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb]]
        stat    = "p95"
      },
    ],
    local.service_widgets,
    [
      {
        title = "Database CPU (%) and credits"
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.db_id],
          ["AWS/RDS", "CPUCreditBalance", "DBInstanceIdentifier", local.db_id, { yAxis = "right" }],
          ["AWS/RDS", "CPUSurplusCreditsCharged", "DBInstanceIdentifier", local.db_id, { yAxis = "right" }],
        ]
        stat = "Average"
      },
      {
        title   = "Database connections"
        metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", local.db_id]]
        stat    = "Maximum"
      },
      {
        title = "Database IOPS (ceiling 3,000)"
        metrics = [
          ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", local.db_id],
          ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", local.db_id],
        ]
        stat = "Average"
      },
      {
        title   = "Database free storage (bytes)"
        metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", local.db_id]]
        stat    = "Minimum"
      },
      {
        title = "NAT gateway traffic (bytes) and port errors"
        metrics = [
          ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", local.network.nat_gateway_id],
          ["AWS/NATGateway", "BytesInFromDestination", "NatGatewayId", local.network.nat_gateway_id],
          ["AWS/NATGateway", "ErrorPortAllocation", "NatGatewayId", local.network.nat_gateway_id, { yAxis = "right" }],
        ]
        stat = "Sum"
      },
    ],
  )
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      for i, w in local.widgets : {
        type   = "metric"
        x      = (i % 2) * 12
        y      = floor(i / 2) * 6
        width  = 12
        height = 6
        properties = {
          title   = w.title
          metrics = w.metrics
          stat    = w.stat
          period  = 300
          region  = var.region
          view    = "timeSeries"
        }
      }
    ]
  })
}

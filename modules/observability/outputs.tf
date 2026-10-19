output "alerts_topic_arn" {
  description = "SNS topic every alarm and event notifies."
  value       = aws_sns_topic.alerts.arn
}

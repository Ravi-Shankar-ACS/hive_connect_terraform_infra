output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix, for CloudWatch dimensions and request-count scaling."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = aws_lb.this.dns_name
}

output "https_listener_arn" {
  description = "HTTPS listener that services attach their host-header rules to."
  value       = aws_lb_listener.https.arn
}

output "web_acl_name" {
  description = "WAF web ACL name."
  value       = aws_wafv2_web_acl.this.name
}

output "certificate_arn" {
  description = "Validated ACM certificate."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

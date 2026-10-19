# One free ACM certificate for all hostnames, validated through the existing
# hosted zone, plus an alias record per hostname pointing at the ALB.

resource "aws_acm_certificate" "this" {
  domain_name               = var.hostnames[0]
  subject_alternative_names = slice(var.hostnames, 1, length(var.hostnames))
  validation_method         = "DNS"

  tags = { Name = var.name }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o
  }

  zone_id         = var.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_route53_record" "alias" {
  for_each = toset(var.hostnames)

  zone_id        = var.zone_id
  name           = each.value
  type           = "A"
  set_identifier = var.dns_weight == null ? null : var.name

  dynamic "weighted_routing_policy" {
    for_each = var.dns_weight == null ? [] : [var.dns_weight]
    content {
      weight = weighted_routing_policy.value
    }
  }

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

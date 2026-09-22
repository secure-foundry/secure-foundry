# dns.tf — split-horizon DNS. The PUBLIC zone exists only to hold ACM's
# domain-validation record (a certificate has to be validated somewhere
# publicly resolvable, even for an otherwise-internal environment). The
# actual application record lives in a PRIVATE zone associated with this
# VPC -- so a non-production environment's hostname only resolves from
# inside the VPC/VPN, never from the open internet, even though its TLS
# certificate is validated the normal, public way.
#
# One manual, one-time step outside Terraform: after this creates the
# public zone, its name servers need to be added as an NS delegation
# record at your domain registrar. Terraform has no API into most
# registrars for this -- see the output below for the values to use.

resource "aws_route53_zone" "public" {
  name = var.domain_name
}

resource "aws_route53_zone" "private" {
  name = var.domain_name
  vpc {
    vpc_id = aws_vpc.this.id
  }
  # A private zone with the SAME name as the public one is deliberate:
  # resolvers inside the VPC prefer the private zone automatically, so
  # the same hostname resolves differently depending on where the query
  # originates -- that's the entire split-horizon mechanism.
}

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
  zone_id = aws_route53_zone.public.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.private.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

output "zone_name_servers" {
  value       = aws_route53_zone.public.name_servers
  description = "Add these as an NS delegation record for var.domain_name at your registrar. One-time, manual, outside Terraform."
}

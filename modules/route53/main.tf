resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = var.tags
}

# ACM Certificate
resource "aws_acm_certificate" "main" {
  domain_name       = "api.${var.domain_name}" # requests a cert specifically for subdomain
  validation_method = "DNS" # proves ownership with DNS record

  lifecycle {
    create_before_destroy = true # prevent downtime don't destroy the cert right away
  }

  tags = var.tags
}

# DNS Validation Record
# ACM says "create CNAME record proving you own the domain" 
# create it automatically in Route53
resource "aws_route53_record" "cert_validation" {
  for_each = { # returns list of DNS records that need to be created for validation
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => { #exact values
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

# Certificate Validation
# tells Terraform to wait until ACM confirms the certificate is validated before continuing
# Validation typically takes 2-5 minutes
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# API Gateway CUstom Domain
# without this, API Gateway only responds to its auto-generated URL
resource "aws_apigatewayv2_domain_name" "main" {
  domain_name = "api.${var.domain_name}" # REgisters custom domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.main.arn
    endpoint_type   = "REGIONAL" #served from a single region
    security_policy = "TLS_1_2"
  }
# waits for the cert to be fully validated before creating the custom domain
  depends_on = [aws_acm_certificate_validation.main]
}

# maps the custom domain to the specific API and stage
resource "aws_apigatewayv2_api_mapping" "main" {
  api_id      = var.api_id # bubbled from the api-gw module
  domain_name = aws_apigatewayv2_domain_name.main.id
  stage       = var.api_stage # same as above
}

resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

    # alias record points to another AWS resource instead of IP
    # the alias record resolves that to the actual IPs behind name and zone_id
  alias {
    name                   = aws_apigatewayv2_domain_name.main.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.main.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = true # Route53 checks if API-GW is healthy before routing traffic
  }
}
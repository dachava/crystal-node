output "name_servers" {
  description = "Paste these into your registrar to point chavastyle.com to Route53"
  value       = aws_route53_zone.main.name_servers
}

output "api_url" {
  description = "Your custom domain API endpoint"
  value       = "https://api.${var.domain_name}"
}

output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = aws_acm_certificate.main.arn
}
output "secret_arn" {
  description = "Secrets Manager ARN for fit-link app secrets (DATABASE_URL + SECRET_KEY)"
  value       = aws_secretsmanager_secret.fit_link.arn
}

output "db_endpoint" {
  description = "RDS instance endpoint (address:port)"
  value       = aws_db_instance.fit_link.endpoint
}

output "fit_link_role_arn" {
  description = "IAM role ARN for fit-link pods (Pod Identity)"
  value       = aws_iam_role.fit_link.arn
}

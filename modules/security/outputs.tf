output "secret_arn" {
  description = "Secrets Manager ARN — reference this in other modules or pipelines"
  value       = aws_secretsmanager_secret.app.arn
}

output "app_role_arn" {
  description = "IAM role ARN for app pods"
  value       = aws_iam_role.app.arn
}
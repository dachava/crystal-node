output "service_account_name" {
  description = "Service account name for debugging"
  value       = kubernetes_service_account.lb_controller.metadata[0].name
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the service account"
  value       = aws_iam_role.lb_controller.arn
}
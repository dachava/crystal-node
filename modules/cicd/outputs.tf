output "ecr_repository_url" {
  description = "ECR repository URL — used in GitHub Actions to push images"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN — configure this in GitHub Actions workflow"
  value       = aws_iam_role.github_actions.arn
}
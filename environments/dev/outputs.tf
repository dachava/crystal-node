# environments/dev/outputs.tf
#surface values after apply

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS"
  value       = module.vpc.private_subnet_ids
}

output "bucket_id" {
  value = module.s3.bucket_id
}

output "bucket_arn" {
  value = module.s3.bucket_arn
}

output "api_endpoint" {
  value = var.deploy_api_gw ? module.api_gw[0].api_endpoint : "api_gw not deployed yet"
}

output "name_servers" {
  value = var.deploy_api_gw ? module.route53[0].name_servers : []
}

output "api_url" {
  value = var.deploy_api_gw ? module.route53[0].api_url : "route53 not deployed yet"
}

output "grafana_service" {
  value = module.observability.grafana_service
}

output "cloudwatch_log_group" {
  value = module.observability.cloudwatch_log_group
}

output "secret_arn" {
  value = module.security.secret_arn
}

output "ecr_repository_url" {
  value = module.cicd.ecr_repository_url
}

output "github_actions_role_arn" {
  value = module.cicd.github_actions_role_arn
}

output "argocd_service" {
  value = module.argocd.argocd_service
}

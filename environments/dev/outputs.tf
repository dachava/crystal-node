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
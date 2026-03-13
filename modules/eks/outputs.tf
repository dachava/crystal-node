output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN consumed by IRSA module when creating pod IAM roles"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "node_security_group_id" {
  description = "Node SG ID referenced by other SG rules in API Gateway and RDS modules"
  value       = aws_security_group.nodes.id
}
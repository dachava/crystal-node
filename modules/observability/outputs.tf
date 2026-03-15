output "grafana_service" {
  description = "Grafana service name — use with kubectl port-forward to access the UI"
  value       = "kube-prometheus-stack-grafana"
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group where container logs are shipped"
  value       = "/aws/containerinsights/${var.cluster_name}/application"
}
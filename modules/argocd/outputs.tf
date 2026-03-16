output "argocd_service" {
  description = "ArgoCD server service use with kubectl port-forward to access the UI"
  value       = "argocd-server"
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "app_name" {
  description = "ArgoCD application name"
  type        = string
  default     = "crystal-app"
}

variable "app_namespace" {
  description = "Kubernetes namespace where the app runs"
  type        = string
  default     = "crystal-app"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}
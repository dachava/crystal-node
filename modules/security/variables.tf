variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace where the app runs"
  type        = string
  default     = "default"
}

variable "app_service_account" {
  description = "Kubernetes service account name for the app pods"
  type        = string
  default     = "crystal-app"
}

variable "db_password" {
  description = "Database password stored in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "api_key" {
  description = "API key stored in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
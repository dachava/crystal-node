# environments/dev/variables.tf

variable "aws_region" {
  description = "AWS region to deploy"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name used across all resources"
  type        = string
  default     = "crystal-cluster"
}

### [EKS] ###

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "desired_nodes" {
  type    = number
  default = 2
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 4
}

### [APPLY step for NLB] ###

variable "deploy_api_gw" {
  description = "Set to true after the NLB is provisioned by kubectl"
  type        = bool
  default     = false
}

variable "api_id" {
  description = "API Gateway ID set automatically after api_gw is deployed"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Root domain name for Route53 and ACM"
  type        = string
  default     = "chavastyle.com"
}

### [OBSERVABILITY] ###

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

### [SECURITY] ###

variable "db_password" {
  description = "Database password for Secrets Manager"
  type        = string
  sensitive   = true
}

variable "api_key" {
  description = "API key for Secrets Manager"
  type        = string
  sensitive   = true
}

variable "app_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "crystal-app"
}

variable "app_service_account" {
  description = "Kubernetes service account for the app pods"
  type        = string
  default     = "crystal-app"
}

### [FIT-LINK RDS] ###

variable "fit_link_db_password" {
  description = "Master password for the fit-link RDS instance"
  type        = string
  sensitive   = true
}

variable "fit_link_secret_key" {
  description = "Application SECRET_KEY for fit-link stored in Secrets Manager"
  type        = string
  sensitive   = true
}

### [CI/CD] ###

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "crystal-app"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "dachava"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "crystal-node"
}
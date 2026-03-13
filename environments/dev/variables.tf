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

# Apply step for the NLB
variable "deploy_api_gw" {
  description = "Set to true after the NLB is provisioned by kubectl"
  type        = bool
  default     = false
}
variable "cluster_name" {
  description = "Name used across all EKS resources"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.31"
}

### [VPC MODULE] ##

variable "vpc_id" {
  description = "VPC ID from the vpc module output"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where nodes will run"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the control plane ENIs"
  type        = list(string)
}

### [NODES] ##

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium" # minimum practical size for EKS nodes
}

variable "desired_nodes" {
  description = "Starting number of nodes"
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "Minimum nodes the autoscaler can scale down to"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum nodes the autoscaler can scale up to"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where RDS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "node_security_group_id" {
  description = "EKS node security group ID, only these nodes may reach port 5432"
  type        = string
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "fitlink"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "fitlink"
}

variable "db_password" {
  description = "Master password for the RDS instance"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "Application SECRET_KEY stored in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

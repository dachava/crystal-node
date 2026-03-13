variable "project_name" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "nlb_listener_arn" {
  description = "NLB listener ARN — API Gateway routes traffic here via VPC Link"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
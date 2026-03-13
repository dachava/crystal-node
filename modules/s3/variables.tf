variable "project_name" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "account_id" {
  description = "AWS account ID for globally unique bucket naming"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
variable "domain_name" {
  description = "Root domain name chavastyle.com"
  type        = string
}

variable "api_id" {
  description = "API Gateway API ID from module.api_gw output"
  type        = string
}

variable "api_stage" {
  description = "API Gateway stage name a.k.a dev, prod, etc."
  type        = string
  default     = "dev"
}

variable "tags" {
  type    = map(string)
  default = {}
}
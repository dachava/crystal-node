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

variable "subdomain" {
  description = "Subdomain prefix a.k.a 'api' for api.chavastyle.com, 'fit' for fit.chavastyle.com, etc."
  type        = string
  default     = "api"
}

variable "zone_id" {
  description = "Route53 hosted zone ID prevents duplicate zone matches"
  type        = string
  default     = "Z09894022ZLA9EVZFW21P"
}
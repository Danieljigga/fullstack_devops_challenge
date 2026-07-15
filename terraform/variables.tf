# In this file put the variables related to the deployment
# variable "variable_name" {
#     type = "type",
#     description = "Description"
# }

variable "project" {
  description = "Name prefix for all resources."
  type        = string
  default     = "rdicidr"
}

variable "aws_region" {
  description = "AWS region. CloudFront is global but its API lives in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "distribution_enabled" {
  description = "Whether the CloudFront distribution is live. Set false to take the app offline after recording."
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "log_retention_days" {
  description = "Days to keep CloudFront access logs before expiry."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

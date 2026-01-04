# ==============================================================================
# Environment Variables
# ==============================================================================

variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "infrastructure_state_bucket" { type = string }
variable "infrastructure_state_key" { type = string }
variable "rds_proxy_endpoint" {
  type    = string
  default = ""
}

variable "rds_security_group_id" {
  type    = string
  default = ""
}

variable "rds_secret_arn" {
  type    = string
  default = ""
}

variable "database_name" {
  type    = string
  default = "vehealth"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "private_subnet_ids" {
  type    = list(string)
  default = []
}

variable "lambda_runtime" {
  type    = string
  default = "nodejs18.x"
}

variable "lambda_memory_size" {
  type    = number
  default = 256
}

variable "lambda_timeout" {
  type    = number
  default = 30
}

variable "log_level" {
  type    = string
  default = "DEBUG"
}

# S3 bucket for document storage
variable "documents_bucket_name" {
  type    = string
  default = ""
}

# ==============================================================================
# Monitoring Variables
# ==============================================================================

variable "api_gateway_id" {
  description = "API Gateway ID for monitoring (from ride-infra)"
  type        = string
  default     = ""
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = null
}

variable "lambda_error_threshold" {
  description = "Number of Lambda errors to trigger alarm"
  type        = number
  default     = 5
}

variable "lambda_duration_threshold" {
  description = "Lambda duration threshold in milliseconds (80% of timeout)"
  type        = number
  default     = 24000
}

variable "api_4xx_threshold" {
  description = "Number of API Gateway 4xx errors to trigger alarm"
  type        = number
  default     = 50
}

variable "api_5xx_threshold" {
  description = "Number of API Gateway 5xx errors to trigger alarm"
  type        = number
  default     = 10
}

variable "api_latency_threshold" {
  description = "API Gateway latency threshold in milliseconds"
  type        = number
  default     = 3000
}

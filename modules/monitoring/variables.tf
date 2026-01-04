# ==============================================================================
# CloudWatch Monitoring Module - Variables
# ==============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch metrics"
  type        = string
}

variable "api_gateway_id" {
  description = "API Gateway ID for monitoring"
  type        = string
}

variable "alarm_email" {
  description = "Email address for alarm notifications (optional)"
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
  default     = 24000 # 24 seconds (80% of 30s timeout)
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
  default     = 3000 # 3 seconds
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

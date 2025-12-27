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

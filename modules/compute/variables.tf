variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "rds_proxy_endpoint" { type = string }
variable "rds_security_group" { type = string }
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
  default = "INFO"
}

variable "documents_bucket_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

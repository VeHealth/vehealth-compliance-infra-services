# ==============================================================================
# VeHealth Compliance Infrastructure - Development Environment
# ==============================================================================

data "terraform_remote_state" "infrastructure" {
  backend = "s3"
  config = {
    region = var.aws_region
    bucket = var.infrastructure_state_bucket
    key    = var.infrastructure_state_key
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "vehealth-compliance-infra-services"
  }
  vpc_id             = try(data.terraform_remote_state.infrastructure.outputs.vpc_id, var.vpc_id)
  private_subnet_ids = try(data.terraform_remote_state.infrastructure.outputs.private_subnet_ids, var.private_subnet_ids)
  rds_proxy_endpoint = try(data.terraform_remote_state.infrastructure.outputs.rds_proxy_endpoint, var.rds_proxy_endpoint)
  rds_security_group = try(data.terraform_remote_state.infrastructure.outputs.rds_security_group_id, var.rds_security_group_id)
}

module "compliance_services" {
  source = "../../modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  aws_region            = var.aws_region
  vpc_id                = local.vpc_id
  private_subnet_ids    = local.private_subnet_ids
  rds_proxy_endpoint    = local.rds_proxy_endpoint
  rds_security_group    = local.rds_security_group
  lambda_runtime        = var.lambda_runtime
  lambda_memory_size    = var.lambda_memory_size
  lambda_timeout        = var.lambda_timeout
  log_level             = var.log_level
  documents_bucket_name = var.documents_bucket_name
  tags                  = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

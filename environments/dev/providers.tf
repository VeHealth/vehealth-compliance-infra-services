provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "vehealth-compliance-infra-services"
      CostCenter  = "compliance-services"
    }
  }
}

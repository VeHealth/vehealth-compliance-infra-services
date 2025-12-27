terraform {
  backend "s3" {
    region         = "us-east-2"
    bucket         = "vehealth-staging-terraform-state"
    key            = "compliance/terraform.tfstate"
    dynamodb_table = "vehealth-staging-terraform-locks"
    encrypt        = true
  }
}

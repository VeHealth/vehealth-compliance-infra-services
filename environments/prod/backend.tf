terraform {
  backend "s3" {
    region         = "us-east-2"
    bucket         = "vehealth-prod-terraform-state"
    key            = "compliance/terraform.tfstate"
    dynamodb_table = "vehealth-prod-terraform-locks"
    encrypt        = true
  }
}

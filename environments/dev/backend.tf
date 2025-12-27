terraform {
  backend "s3" {
    region         = "us-east-2"
    bucket         = "vehealth-dev-terraform-state"
    key            = "compliance/terraform.tfstate"
    dynamodb_table = "vehealth-dev-terraform-locks"
    encrypt        = true
  }
}

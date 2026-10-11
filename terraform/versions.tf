terraform {
  required_version = ">= 0.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket  = "enoch-tf-state-bucket"
    key     = "stackit-titanic-app/terraform.tfstate"
    region  = "us-east-1"
    profile = "stackprog-dev"
  }
}

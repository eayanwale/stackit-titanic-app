provider "aws" {
  region  = var.AWS_REGION
  profile = "stackprog-dev"

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.ENVIRONMENT
      Project     = var.APP_NAME
    }
  }
}

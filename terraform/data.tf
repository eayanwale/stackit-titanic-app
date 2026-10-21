# Current AWS account, used to build ARNs
data "aws_caller_identity" "current" {}

# Newest golden image built by packer/image.pkr.hcl (shared from the automation account)
data "aws_ami" "golden" {
  most_recent = true
  owners      = [var.AMI_OWNER_ACCOUNT_ID]

  filter {
    name   = "name"
    values = ["${var.AMI_NAME_PREFIX}-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# RDS master password, kept in SSM so it's never in the code
data "aws_ssm_parameter" "db_password" {
  name            = "${var.SSM_PREFIX}/DB_PASSWORD"
  with_decryption = true
}

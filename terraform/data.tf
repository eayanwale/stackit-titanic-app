data "aws_caller_identity" "current" {}

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

data "aws_ssm_parameter" "db_password" {
  name            = "${var.SSM_PREFIX}/DB_PASSWORD"
  with_decryption = true
}

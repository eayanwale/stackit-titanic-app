data "aws_caller_identity" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../titanic-survival"
  output_path = "${path.module}/app.zip"
  excludes    = [".env", ".venv", "__pycache__", "instance", "titanic.db"]
}

resource "random_password" "db_password" {
  length  = 24
  special = false
}

packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_instance_type" {
  default = "t3.micro"
}

variable "ami_name" {
  default = "stack-titanic-app"
}

variable "component" {
  default = "titanic"
}

variable "aws_region" {
  default = "us-east-1"
}

data "amazon-ami" "al2023" {
  region = "${var.aws_region}"
  filters = {
    name                = "al2023-ami-2023*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  owners      = ["amazon"]
  most_recent = true
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "amazon-ebs" "amazon_ebs" {
  ami_name      = "${var.ami_name}-${local.timestamp}"
  encrypt_boot  = false
  instance_type = "${var.aws_instance_type}"
  region        = "${var.aws_region}"
  source_ami    = "${data.amazon-ami.al2023.id}"
  ssh_pty       = true
  ssh_timeout   = "5m"
  ssh_username  = "ec2-user"

  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    encrypted             = false
    volume_size           = 10
    volume_type           = "gp3"
  }

  tags = {
    Name      = "${var.ami_name}-${local.timestamp}"
    Component = "${var.component}"
  }

  snapshot_tags = {
    Name      = "${var.ami_name}-${local.timestamp}"
    Component = "${var.component}"
  }
}

build {
  sources = ["source.amazon-ebs.amazon_ebs"]

  provisioner "file" {
    source      = "${path.root}/../titanic-survival"
    destination = "/tmp"
  }

  provisioner "shell" {
    script = "${path.root}/setup.sh"
  }

  post-processor "manifest" {
    output = "${path.root}/packer-manifest.json"
  }
}

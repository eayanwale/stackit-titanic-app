variable "AWS_REGION" {
  type    = string
  default = "us-east-1"
}

variable "ENVIRONMENT" {
  type    = string
  default = "Development"
}

variable "APP_NAME" {
  type    = string
  default = "titanic-survival"
}

variable "VPC_ID" {
  type    = string
  default = "vpc-0513533f2f1efbfbd"
}

variable "SUBNET_A" {
  type    = string
  default = "subnet-0cd407c60e5fc2301"
}

variable "SUBNET_B" {
  type    = string
  default = "subnet-004ef57820b789ae3"
}

variable "PRIVATE_CIDR_A" {
  type    = string
  default = "172.31.200.0/24"
}

variable "PRIVATE_CIDR_B" {
  type    = string
  default = "172.31.201.0/24"
}

variable "AMI_NAME_PREFIX" {
  type    = string
  default = "stack-titanic-app"
}

variable "AMI_OWNER_ACCOUNT_ID" {
  type    = string
  default = "604175034089"
}

variable "INSTANCE_TYPE" {
  type    = string
  default = "t3.small"
}

variable "DB_INSTANCE_CLASS" {
  type    = string
  default = "db.t3.micro"
}

variable "SAGEMAKER_ENDPOINT_NAME" {
  type    = string
  default = ""
}

variable "SSM_PREFIX" {
  type    = string
  default = "/stack/titanic"
}

variable "APP_USERNAME" {
  type    = string
  default = "admin"
}

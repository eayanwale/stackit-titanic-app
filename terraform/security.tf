resource "aws_security_group" "alb" {
  name        = "${var.APP_NAME}-alb-sg"
  description = "Public HTTP to the load balancer"
  vpc_id      = var.VPC_ID

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.APP_NAME}-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.APP_NAME}-app-sg"
  description = "Gunicorn port from the load balancer only"
  vpc_id      = var.VPC_ID

  ingress {
    description     = "App port from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.APP_NAME}-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.APP_NAME}-db-sg"
  description = "Postgres from the app tier only"
  vpc_id      = var.VPC_ID

  ingress {
    description     = "Postgres from app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.APP_NAME}-db-sg"
  }
}

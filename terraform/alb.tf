# Public ALB in the public subnets - the app's entry point
resource "aws_lb" "app" {
  name               = "${var.APP_NAME}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [var.SUBNET_A, var.SUBNET_B]
}

# Gunicorn listens on 8000; /healthz tells the ALB an instance is ready
resource "aws_lb_target_group" "app" {
  name     = "${var.APP_NAME}-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = var.VPC_ID

  health_check {
    path    = "/healthz"
    matcher = "200"
  }
}

# HTTP :80 forwards everything to the target group (HTTPS not set up yet)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

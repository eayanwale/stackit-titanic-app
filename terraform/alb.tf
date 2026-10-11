resource "aws_lb" "app" {
  name               = "${var.APP_NAME}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [var.SUBNET_A, var.SUBNET_B]
}

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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Launch template: golden AMI, private IP only, IMDSv2 required.
# user-data writes the .env (secrets from SSM, DB address from RDS) and starts the service.
resource "aws_launch_template" "app" {
  name_prefix            = "${var.APP_NAME}-lt"
  image_id               = data.aws_ami.golden.id
  instance_type          = var.INSTANCE_TYPE
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = base64encode(templatefile("${path.module}/user-data.tftpl", {
    aws_region   = var.AWS_REGION
    ssm_prefix   = var.SSM_PREFIX
    app_username = var.APP_USERNAME
    endpoint     = var.SAGEMAKER_ENDPOINT_NAME
    db_host      = aws_db_instance.db.address
    db_user      = aws_db_instance.db.username
    db_name      = aws_db_instance.db.db_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.APP_NAME}-instance"
    }
  }
}

# ASG in the private subnets behind the ALB target group
resource "aws_autoscaling_group" "app" {
  name                      = "${var.APP_NAME}-asg"
  min_size                  = 1
  max_size                  = 2
  desired_capacity          = 1
  health_check_type         = "ELB"
  health_check_grace_period = 300
  force_delete              = true
  vpc_zone_identifier       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  target_group_arns         = [aws_lb_target_group.app.arn]

  # A concrete version (not "$Latest") so a new AMI changes this value and
  # triggers the instance_refresh below
  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # Roll instances one at a time, keeping full capacity, when the template changes
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      instance_warmup        = 180
    }
  }

  # Instances need the NAT route in place before they boot, or user-data can't reach SSM
  depends_on = [
    aws_route_table_association.private_a,
    aws_route_table_association.private_b,
    aws_nat_gateway.nat,
  ]

  tag {
    key                 = "Name"
    value               = "${var.APP_NAME}-instance"
    propagate_at_launch = true
  }
}

# Scale out when average CPU goes above 70%
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.APP_NAME}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

output "app_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "db_endpoint" {
  value = aws_db_instance.db.address
}

output "app_username" {
  value = var.APP_USERNAME
}

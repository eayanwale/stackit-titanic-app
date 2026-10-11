resource "aws_db_subnet_group" "db" {
  name       = "${var.APP_NAME}-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.APP_NAME}-subnet-group"
  }
}

resource "aws_db_instance" "db" {
  identifier             = "${var.APP_NAME}-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.DB_INSTANCE_CLASS
  allocated_storage      = 20
  db_name                = "titanic"
  username               = "titanic"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
}

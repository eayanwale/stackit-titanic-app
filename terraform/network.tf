data "aws_subnet" "public_a" {
  id = var.SUBNET_A
}

data "aws_subnet" "public_b" {
  id = var.SUBNET_B
}

resource "aws_subnet" "private_a" {
  vpc_id            = var.VPC_ID
  cidr_block        = var.PRIVATE_CIDR_A
  availability_zone = data.aws_subnet.public_a.availability_zone

  tags = {
    Name = "${var.APP_NAME}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = var.VPC_ID
  cidr_block        = var.PRIVATE_CIDR_B
  availability_zone = data.aws_subnet.public_b.availability_zone

  tags = {
    Name = "${var.APP_NAME}-private-b"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.APP_NAME}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.SUBNET_A

  tags = {
    Name = "${var.APP_NAME}-nat"
  }
}

resource "aws_route_table" "private" {
  vpc_id = var.VPC_ID

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.APP_NAME}-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

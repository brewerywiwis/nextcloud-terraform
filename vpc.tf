resource "aws_vpc" "nextcloud-vpc" {
  cidr_block = "172.16.0.0/16"
  tags = {
    Name = "nextcloud-vpc"
  }
}

resource "aws_subnet" "public-subnet" {
  depends_on = [
    aws_vpc.nextcloud-vpc
  ]
  vpc_id            = aws_vpc.nextcloud-vpc.id
  cidr_block        = "172.16.1.0/24"
  availability_zone = var.availability_zone
  tags = {
    Name = "nextcloud-public-subnet"
  }
}

resource "aws_subnet" "local-subnet" {
  depends_on = [
    aws_vpc.nextcloud-vpc
  ]
  vpc_id            = aws_vpc.nextcloud-vpc.id
  cidr_block        = "172.16.2.0/24"
  availability_zone = var.availability_zone
  tags = {
    Name = "nextcloud-local-subnet"
  }
}

resource "aws_subnet" "nat-subnet" {
  depends_on = [
    aws_vpc.nextcloud-vpc,
  ]
  vpc_id            = aws_vpc.nextcloud-vpc.id
  cidr_block        = "172.16.3.0/24"
  availability_zone = var.availability_zone
  tags = {
    Name = "nextcloud-nat-subnet"
  }
}

resource "aws_internet_gateway" "internet-gateway" {
  depends_on = [
    aws_vpc.nextcloud-vpc,
  ]
  vpc_id = aws_vpc.nextcloud-vpc.id
  tags = {
    Name = "nextcloud-igw"
  }
}
resource "aws_route_table" "igw-routing-table" {
  depends_on = [
    aws_vpc.nextcloud-vpc,
    aws_internet_gateway.internet-gateway
  ]
  vpc_id = aws_vpc.nextcloud-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway.id
  }
  tags = {
    Name = "internet-gateway-routing-table"
  }
}
resource "aws_route_table_association" "igw-table-association" {
  depends_on = [
    aws_subnet.public-subnet,
    aws_route_table.igw-routing-table
  ]
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.igw-routing-table.id
}

resource "aws_eip" "nat-gateway-eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat-gateway" {
  depends_on = [
    aws_eip.nat-gateway-eip,
    aws_subnet.public-subnet
  ]
  allocation_id = aws_eip.nat-gateway-eip.id
  subnet_id     = aws_subnet.public-subnet.id
  tags = {
    Name = "nextcloud-nat-gateway"
  }
}

resource "aws_route_table" "nat-gateway-routing-table" {
  depends_on = [
    aws_nat_gateway.nat-gateway
  ]
  vpc_id = aws_vpc.nextcloud-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gateway.id
  }
  tags = {
    Name = "nat-gateway-routing-table"
  }

}

resource "aws_route_table_association" "nat-gateway-routing-table-asscociation" {
  depends_on = [
    aws_route_table.nat-gateway-routing-table,
    aws_subnet.nat-subnet
  ]
  subnet_id      = aws_subnet.nat-subnet.id
  route_table_id = aws_route_table.nat-gateway-routing-table.id
}

resource "aws_security_group" "app-sg" {

  depends_on = [
    aws_vpc.nextcloud-vpc,
    aws_subnet.public-subnet,
    aws_subnet.nat-subnet
  ]

  description = "app security group"
  name        = "next cloud app sg"
  vpc_id      = aws_vpc.nextcloud-vpc.id

  ingress {
    description = "in"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "in"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "in"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "out"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "local-db-sg" {
  depends_on = [
    aws_vpc.nextcloud-vpc,
    aws_subnet.local-subnet,
  ]

  description = "local db subnet security group"
  name        = "next cloud local db sg"
  vpc_id      = aws_vpc.nextcloud-vpc.id

  ingress {
    description     = "in"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["172.16.2.0/24"]
    security_groups = [aws_security_group.app-sg.id]
  }

  ingress {
    description     = "in"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    cidr_blocks     = ["172.16.2.0/24"]
    security_groups = [aws_security_group.app-sg.id]
  }

  ingress {
    description     = "in"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = ["172.16.2.0/24"]
    security_groups = [aws_security_group.app-sg.id]
  }

  egress {
    description = "out"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "local-app-sg" {
  depends_on = [
    aws_vpc.nextcloud-vpc,
    aws_subnet.local-subnet,
  ]

  description = "local app subnet security group"
  name        = "next cloud local app sg"
  vpc_id      = aws_vpc.nextcloud-vpc.id

  ingress {
    description     = "in"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    cidr_blocks     = ["172.16.2.0/24"]
    security_groups = [aws_security_group.app-sg.id]
  }

  egress {
    description = "out"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["172.16.2.0/24"]
  }
}
resource "aws_security_group" "db-sg" {
  depends_on = [
    aws_vpc.nextcloud-vpc,
    aws_subnet.public-subnet,
    aws_subnet.nat-subnet,
  ]

  description = "db security group"
  name        = "next cloud db sg"
  vpc_id      = aws_vpc.nextcloud-vpc.id

  ingress {
    description     = "in"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.app-sg.id]
  }

  ingress {
    description     = "in"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    cidr_blocks     = ["172.168.1.0/24"]
    security_groups = [aws_security_group.app-sg.id]
  }

  ingress {
    description     = "in"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = ["172.168.1.0/24"]
    security_groups = [aws_security_group.app-sg.id]
  }

  egress {
    description = "out"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "app-public-nic" {
  depends_on = [
    aws_subnet.public-subnet,
    aws_security_group.app-sg
  ]
  subnet_id   = aws_subnet.public-subnet.id
  private_ips = ["172.16.1.100"]
  tags = {
    Name = "nextcloud-app-public-nic"
  }
  security_groups = [aws_security_group.app-sg.id]
}

resource "aws_eip" "app-nic-eip" {
  vpc                       = true
  network_interface         = aws_network_interface.app-public-nic.id
  associate_with_private_ip = "172.16.1.100"
}

resource "aws_network_interface" "local-app-nic" {
  depends_on = [
    aws_subnet.nat-subnet
  ]
  subnet_id   = aws_subnet.local-subnet.id
  private_ips = ["172.16.2.100"]
  tags = {
    Name = "nextcloud-local-app-nic"
  }
  security_groups = [aws_security_group.local-app-sg.id]
}

resource "aws_network_interface" "local-db-nic" {
  depends_on = [
    aws_subnet.nat-subnet
  ]
  subnet_id   = aws_subnet.local-subnet.id
  private_ips = ["172.16.2.200"]
  tags = {
    Name = "nextcloud-local-db-nic"
  }
  security_groups = [aws_security_group.local-db-sg.id]
}
resource "aws_network_interface" "nat-db-nic" {
  depends_on = [
    aws_subnet.nat-subnet
  ]
  subnet_id   = aws_subnet.nat-subnet.id
  private_ips = ["172.16.3.100"]
  tags = {
    Name = "nextcloud-nat-db-nic"
  }
  security_groups = [aws_security_group.db-sg.id]
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create a VPC
resource "aws_vpc" "jenkins_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "jenkins_vpc"
  }
}

# Subnet Publica
resource "aws_subnet" "jenkins_subnet" {
  vpc_id                  = aws_vpc.jenkins_vpc.id
  cidr_block              = "10.0.100.0/24" # Subnet pública
  map_public_ip_on_launch = true

  tags = {
    Name = "jenkins_subnet"
  }
}

# Crear un AWS Internet Gateway (puerta de enlace a internet)
resource "aws_internet_gateway" "jenkins_gateway" {
  vpc_id = aws_vpc.jenkins_vpc.id

  tags = {
    Name = "jenkins_gateway"
  }
}

# Crear una tabla de rutas
resource "aws_route_table" "jenkins_route_table" {
  vpc_id = aws_vpc.jenkins_vpc.id

  tags = {
    Name = "jenkins_route_table"
  }
}

# Crear una ruta para permitir tráfico a Internet
resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.jenkins_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.jenkins_gateway.id
}

# Asociar la Subnet con la Tabla de Enrutamiento
resource "aws_route_table_association" "jenkins_subnet_association" {
  subnet_id      = aws_subnet.jenkins_subnet.id
  route_table_id = aws_route_table.jenkins_route_table.id
}

# Security groups
resource "aws_security_group" "security" {
  vpc_id      = aws_vpc.jenkins_vpc.id
  name        = "security"
  description = "Allow HTTP on port 80, 8080 and SSH on port 22"

  # Regla para permitir tráfico HTTP (puerto 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Permitir desde cualquier IP
  }

  # Regla para permitir tráfico HTTP (puerto 8080, Jenkins)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Permitir desde cualquier IP
  }

  # Regla para permitir tráfico SSH (puerto 22)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Permitir desde cualquier IP (puedes restringirlo a una IP específica por seguridad)
  }

  # Regla para permitir todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Crear un Key Pair (clave SSH) en AWS
resource "aws_key_pair" "jenkins_key" {
  key_name   = "mi-clave-ssh"  # Nombre de la clave SSH
  public_key = file("../aopjenkins.pub")  # Ruta de la clave pública SSH
}

# Crear una Instancia EC2 para Jenkins
resource "aws_instance" "jenkins_server" {
  ami             = "ami-071226ecf16aa7d96"  # Amazon Linux 2 AMI (ID actualizada)
  instance_type   = "t2.medium"
  key_name        = aws_key_pair.jenkins_key.key_name
  security_groups = [aws_security_group.security.id]  # Cambiado a 'id'
  subnet_id       = aws_subnet.jenkins_subnet.id

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              curl -fsSL https://get.docker.com | sh
              docker run -d -p 8080:8080 -p 50000:50000 jenkins/jenkins:lts
              EOF

  tags = {
    Name = "JenkinsServer"
  }

  associate_public_ip_address = true

  depends_on = [aws_security_group.security]  # Esta es la dependencia adicional
}


# Salida con la URL de Jenkins
output "jenkins_url" {
  value = "http://${aws_instance.jenkins_server.public_ip}:8080"
}

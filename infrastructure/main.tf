terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# variables
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "repo_url" {
  type        = string
  description = "url del repo"
  default     = "https://github.com/josueiteso/to-do-list-api"
}

variable "app_file" {
  type        = string
  description = "nombre del archivo python de la aplicacion"
  default     = "tasks.py"
}

variable "permitted_ip_cidr" {
  type        = string
  description = "ip permitida para SSH"
  default     = "0.0.0.0/0" # la puse publica solo para hacer mas facil el lab
}

provider "aws" {
  region = var.region
}

# ami de ubntu server
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# key Pair
resource "aws_key_pair" "tasks" {
  key_name   = "tasks-key"
  public_key = file("${path.module}/../tasks-key.pub")
}

# security group
resource "aws_security_group" "tasks" {
  name        = "tasks-app-sg"
  description = "SSH y puerto para la app"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.permitted_ip_cidr]
  }

  ingress {
    description = "Flask app"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# instancia EC2
resource "aws_instance" "tasks" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.tasks.key_name
  vpc_security_group_ids      = [aws_security_group.tasks.id]
  associate_public_ip_address = true

  # recrea la instancia si se cambia el script
  user_data_replace_on_change = true

  user_data = <<-EOT
    #!/bin/bash
    set -e

    # dependencias del sistema
    apt-get update -y
    apt-get install -y git python3-venv python3-pip

    # clonar el repo
    git clone ${var.repo_url} /opt/app

    # venv y flask
    python3 -m venv /opt/app/venv
    /opt/app/venv/bin/pip install flask

    # servicio systemd para que la app arranque al boot
    cat > /etc/systemd/system/tasks.service <<EOF
    [Unit]
    Description=Flask Tasks App
    After=network.target

    [Service]
    WorkingDirectory=/opt/app
    ExecStart=/opt/app/venv/bin/python ${var.app_file}
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOF

    systemctl daemon-reload
    systemctl enable --now tasks.service
  EOT

  tags = {
    Name = "tasks-app"
  }
}

# outputs
output "public_ip" {
  value = aws_instance.tasks.public_ip
}

output "tasks_url" {
  value = "http://${aws_instance.tasks.public_ip}:5000/tasks"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {}

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

variable "alert_email" {
  type        = string
  description = "correo que recibe las notificaciones de las alarmas"
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

# security group EC2
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

# credenciales de RDS desde secrets manmager
resource "random_password" "db" {
  length  = 24
  special = false # evita caracteres especiales
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "tasks-app/db-credentials"
  recovery_window_in_days = 0 # permite borrar y recrear con el mismo nombre
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = aws_db_instance.tasks.username
    password = random_password.db.result
    host     = aws_db_instance.tasks.address
    port     = aws_db_instance.tasks.port
    dbname   = aws_db_instance.tasks.db_name
  })
}

# security groups rds
resource "aws_security_group" "db" {
  name        = "tasks-rds-sg"
  description = "connecion a postgresql solo desde la EC2 de la app"

  ingress {
    description     = "postgreSQL desde la app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }
}

# instancia RDS
resource "aws_db_instance" "tasks" {
  identifier        = "tasks-db"
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "tasksdb"
  username = "tasksadmin"
  password = random_password.db.result

  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 0
  skip_final_snapshot     = true
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

  iam_instance_profile = "LabInstanceProfile"

  user_data = <<-EOT
    #!/bin/bash
    set -e

    # instalamos python y postgresql client
    apt-get update -y
    apt-get install -y git python3-venv python3-pip postgresql-client unzip libpq-dev gcc python3-dev

    # clonar el repo
    mkdir -p /opt/tasks/releases
    git clone ${var.repo_url} /opt/tasks/releases/initial
    ln -sfn /opt/tasks/releases/initial /opt/tasks/current

    # instalar dependencias
    python3 -m venv /opt/tasks/venv
    /opt/tasks/venv/bin/pip install -r /opt/tasks/current/requirements.txt

    # version inicial (el deploy la sobrescribe con el tag)
    echo "APP_VERSION=initial" > /etc/tasks.env

    # servicio systemd para que la app arranque al boot
    cat > /etc/systemd/system/tasks.service <<EOF
    [Unit]
    Description=Flask Tasks App
    After=network.target

    [Service]
    WorkingDirectory=/opt/tasks/current
    EnvironmentFile=/etc/tasks.env
    Environment=DB_SECRET_NAME=${aws_secretsmanager_secret.db.name}
    Environment=AWS_REGION=${var.region}
    ExecStart=/opt/tasks/venv/bin/python ${var.app_file}
    Restart=always
    RestartSec=5

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

# topico sns
resource "aws_sns_topic" "alerts" {
  name = "tasks-app-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# alarma 1: status check de la EC2
# con la metrica nativa de AWS StatusCheckFailed
resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  alarm_name          = "tasks-ec2-status-check-failed"
  alarm_description   = "La instancia EC2 fallo sus status checks"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.tasks.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# alarma 2: errores al leer o escribir base de datos
# con la metrica personal DbErrors
resource "aws_cloudwatch_metric_alarm" "db_errors" {
  alarm_name          = "tasks-app-db-errors"
  alarm_description   = "La app reporta errores al leer o escribir en RDS"
  namespace           = "TasksApp"
  metric_name         = "DbErrors"
  dimensions          = { Service = "tasks-app" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# alarma 3: pico anormal de creacion de tareas
# con la metrica personal TasksCreated
resource "aws_cloudwatch_metric_alarm" "tasks_created_spike" {
  alarm_name          = "tasks-app-tasks-created-spike"
  alarm_description   = "Se crean demasiadas tareas en poco tiempo"
  namespace           = "TasksApp"
  metric_name         = "TasksCreated"
  dimensions          = { Service = "tasks-app" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 20
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# outputs
output "public_ip" {
  value = aws_instance.tasks.public_ip
}

output "tasks_url" {
  value = "http://${aws_instance.tasks.public_ip}:5000/tasks"
}

output "db_endpoint" {
  value = aws_db_instance.tasks.address
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

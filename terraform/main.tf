terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  cloud {
    organization = "jay-stockhausen"

    workspaces {
      name = "memcached-testing"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      env = "test"
    }
  }
}

resource "aws_security_group" "stocks_db" {
  name        = "stocks-db-sg"
  description = "Security group for stocks RDS instance."

  tags = {
    Name = "postgres-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "stocks_db" {
  security_group_id = aws_security_group.stocks_db.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 5432
  ip_protocol = "tcp"
  to_port     = 5432
}

resource "aws_vpc_security_group_egress_rule" "stocks_db" {
  security_group_id = aws_security_group.stocks_db.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_db_instance" "stocks" {
  allocated_storage          = 20
  db_name                    = "stocks"
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = "db.t3.micro"
  username                   = "service"
  password                   = var.stock_db_pw
  auto_minor_version_upgrade = false
  skip_final_snapshot        = true

  publicly_accessible    = true
  vpc_security_group_ids = [
    aws_security_group.stocks_db.id
  ]

  tags = {
    Name = "stocks"
  }
}

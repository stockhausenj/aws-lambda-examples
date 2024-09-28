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

resource "aws_db_instance" "default" {
  allocated_storage          = 20
  db_name                    = "stocks"
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = "db.t3.micro"
  username                   = "service"
  password                   = var.stock_db_pw
  auto_minor_version_upgrade = false
  skip_final_snapshot        = true
}

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

data "terraform_remote_state" "personal_aws" {
  backend = "remote"
  config = {
    organization = "jay-stockhausen"
    workspaces = {
      name = "personal-aws"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "private_subnets" {
  tags = {
    kind = "private"
  }
}

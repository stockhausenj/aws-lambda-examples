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

data "aws_ecr_image" "third_party_api" {
  repository_name = data.terraform_remote_state.personal_aws.outputs.ecr_personal_test_repo_name
  image_tag       = "third-party-sync"
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

resource "aws_secretsmanager_secret" "db_access" {
  name = "db_access"
}

resource "aws_secretsmanager_secret_version" "db_access_pw" {
  secret_id     = aws_secretsmanager_secret.db_access.id
  secret_string = var.stock_db_pw
}

resource "aws_secretsmanager_secret" "third_party_api" {
  name = "third_party_api"
}

resource "aws_secretsmanager_secret_version" "third_party_api_key" {
  secret_id     = aws_secretsmanager_secret.third_party_api.id
  secret_string = var.third_party_api_key
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "third_party_api" {
  name        = "LambdaSecretsAccessPolicy"
  description = "IAM policy for accessing secrets in AWS Secrets Manager"
  
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue"
        ],
        "Resource": [
          aws_secretsmanager_secret.db_access.arn,
          aws_secretsmanager_secret.third_party_api.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "third_party_api" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.third_party_api.arn
}

resource "aws_lambda_function" "third_party_api" {
  function_name    = "python_container_lambda"
  role             = aws_iam_role.lambda_exec_role.arn
  package_type     = "Image"
  image_uri        = data.aws_ecr_image.third_party_api.image_uri
  memory_size      = 128
  timeout          = 60

  environment {
    variables = {
      RDS_HOST                = aws_db_instance.stocks.address
      RDS_DATABASE            = aws_db_instance.stocks.db_name
      RDS_USER                = aws_db_instance.stocks.username
      RDS_PASSWORD_ARN        = aws_secretsmanager_secret.db_access.arn 
      THIRD_PARTY_API_KEY_ARN = aws_secretsmanager_secret.third_party_api.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "third_party_api" {
  name                = "third_party_api_cron_schedule"
  description         = "Run Lambda every hour Monday-Friday"
  schedule_expression = "cron(0 * ? * 2-6 *)"  # Cron expression for Monday-Friday, every hour
}

resource "aws_lambda_permission" "cloudwatch_third_party_api" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.third_party_api.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.third_party_api.arn
}

resource "aws_cloudwatch_event_target" "third_party_api" {
  rule      = aws_cloudwatch_event_rule.third_party_api.name
  target_id = "lambda_target"
  arn       = aws_lambda_function.third_party_api.arn
}

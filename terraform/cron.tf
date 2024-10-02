resource "aws_ecr_repository" "cron" {
  name                 = "personal/cron"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "cron" {
  repository = aws_ecr_repository.cron.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 1 image",
            "selection": {
                "tagStatus": "untagged",
                "countType": "imageCountMoreThan",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

data "aws_ecr_image" "cron" {
  repository_name = aws_ecr_repository.cron.name
  image_tag       = "latest"
}

resource "aws_security_group" "cron_db" {
  name        = "cron-db"
  description = "Security group for cron RDS instance."
}

resource "aws_vpc_security_group_ingress_rule" "cron_db" {
  security_group_id = aws_security_group.cron_db.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 5432
  ip_protocol = "tcp"
  to_port     = 5432
}

resource "aws_vpc_security_group_egress_rule" "cron_db" {
  security_group_id = aws_security_group.cron_db.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_db_instance" "cron" {
  allocated_storage          = 20
  db_name                    = "cron"
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = "db.t3.micro"
  username                   = "service"
  password                   = var.cron_db_pw
  auto_minor_version_upgrade = false
  skip_final_snapshot        = true

  publicly_accessible = true
  vpc_security_group_ids = [
    aws_security_group.cron_db.id
  ]
}

resource "aws_secretsmanager_secret" "cron_db" {
  name = "db_access"
}

resource "aws_secretsmanager_secret_version" "cron_db_pw" {
  secret_id     = aws_secretsmanager_secret.cron_db.id
  secret_string = var.cron_db_pw
}

resource "aws_iam_role" "cron" {
  name = "cron"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cron_basic_exec" {
  role       = aws_iam_role.cron.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "cron_secrets" {
  name        = "cron"
  description = "Allow Lambda to access certain secrets in Secret Manager."

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue"
        ],
        "Resource" : [
          aws_secretsmanager_secret.cron_db.arn,
          aws_secretsmanager_secret.external_api.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cron_secrets" {
  role       = aws_iam_role.cron.name
  policy_arn = aws_iam_policy.cron_secrets.arn
}

resource "aws_lambda_function" "cron" {
  function_name = "cron"
  role          = aws_iam_role.cron.arn
  package_type  = "Image"
  image_uri     = data.aws_ecr_image.cron.image_uri
  memory_size   = 128
  timeout       = 60

  environment {
    variables = {
      RDS_HOST                = aws_db_instance.cron.address
      RDS_DATABASE            = aws_db_instance.cron.db_name
      RDS_USER                = aws_db_instance.cron.username
      RDS_PASSWORD_ARN        = aws_secretsmanager_secret.cron_db.arn
      THIRD_PARTY_API_KEY_ARN = aws_secretsmanager_secret.external_api.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "cron" {
  name                = "cron_schedule"
  description         = "Run Lambda every hour Monday-Friday"
  schedule_expression = "cron(0 14-20 ? * MON-FRI *)" # Try to match stock market hours. Which is 9:30 AM to 4:00 PM ET.
}

resource "aws_lambda_permission" "cloudwatch_cron" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cron.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron.arn
}

resource "aws_cloudwatch_event_target" "cron" {
  rule      = aws_cloudwatch_event_rule.cron.name
  target_id = "lambda_target"
  arn       = aws_lambda_function.cron.arn
}

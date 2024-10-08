resource "aws_ecr_repository" "api_gw_nat" {
  name                 = "personal/api_gw_nat"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "api_gw_nat" {
  repository = aws_ecr_repository.api_gw_nat.name

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

resource "aws_security_group" "api_gw_nat_memcached" {
  name        = "api-gw-nat-memcached"
  description = "Security group for api_gw_nat Memcached."
}

resource "aws_vpc_security_group_ingress_rule" "api_gw_nat_memcached" {
  security_group_id = aws_security_group.api_gw_nat_memcached.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_apigatewayv2_api" "api_gw_nat" {
  name          = "api_gw_nat"
  protocol_type = "HTTP"
}

resource "aws_elasticache_subnet_group" "api_gw_nat" {
  name       = "api-gw-nat"
  subnet_ids = data.aws_subnets.private_subnets.ids

  description = "ElastiCache Subnet Group for private subnets"
}

resource "aws_elasticache_cluster" "api_gw_nat" {
  cluster_id           = "api-gw-nat"
  engine               = "memcached"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.6"
  port                 = 11211
  subnet_group_name    = aws_elasticache_subnet_group.api_gw_nat.name
  security_group_ids   = [aws_security_group.api_gw_nat_memcached.id]
}

data "aws_ecr_image" "api_gw_nat" {
  repository_name = aws_ecr_repository.api_gw_nat.name
  image_tag       = "latest"
}

resource "aws_iam_role" "api_gw_nat" {
  name = "api_gw_nat"

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

resource "aws_iam_role_policy_attachment" "api_gw_nat_basic_exec" {
  role       = aws_iam_role.api_gw_nat.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "api_gw_nat_ec2" {
  name        = "api_gw_nat_ec2"
  description = "Allow Lambda to create network interfaces. Necessary for NAT design."

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gw_nat_ec2" {
  role       = aws_iam_role.api_gw_nat.name
  policy_arn = aws_iam_policy.api_gw_nat_ec2.arn
}

resource "aws_iam_policy" "api_gw_nat_secrets" {
  name        = "api_gw_nat_secrets"
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
          aws_secretsmanager_secret.external_api.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gw_nat_secrets" {
  role       = aws_iam_role.api_gw_nat.name
  policy_arn = aws_iam_policy.api_gw_nat_secrets.arn
}

resource "aws_security_group" "api_gw_nat_lambda" {
  name        = "api-gw-nat-lambda"
  description = "Security group for api_gw_nat Lambda."
}

resource "aws_vpc_security_group_egress_rule" "api_gw_nat_lambda" {
  security_group_id = aws_security_group.api_gw_nat_lambda.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_lambda_function" "api_gw_nat" {
  function_name = "api_gw_nat"
  role          = aws_iam_role.api_gw_nat.arn
  package_type  = "Image"
  image_uri     = data.aws_ecr_image.api_gw_nat.image_uri
  memory_size   = 128
  timeout       = 60

  vpc_config {
    subnet_ids         = data.aws_subnets.private_subnets.ids
    security_group_ids = [aws_security_group.api_gw_nat_lambda.id]
  }

  environment {
    variables = {
      THIRD_PARTY_API_KEY_ARN = aws_secretsmanager_secret.external_api.arn
      MEMCACHED_ENDPOINT      = aws_elasticache_cluster.api_gw_nat.cluster_address
    }
  }
}

resource "aws_apigatewayv2_integration" "api_gw_nat" {
  api_id                 = aws_apigatewayv2_api.api_gw_nat.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_gw_nat.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api_gw_nat" {
  api_id    = aws_apigatewayv2_api.api_gw_nat.id
  route_key = "GET /foo"

  target = "integrations/${aws_apigatewayv2_integration.api_gw_nat.id}"
}

resource "aws_apigatewayv2_stage" "api_gw_nat" {
  api_id      = aws_apigatewayv2_api.api_gw_nat.id
  name        = "dev"
  auto_deploy = true

  route_settings {
    route_key              = "GET /foo"
    throttling_rate_limit  = 1 # RPS
    throttling_burst_limit = 1 # RPS
  }
}

resource "aws_lambda_permission" "api_gw_nat" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_gw_nat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api_gw_nat.execution_arn}/*/*"
}

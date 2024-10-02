resource "aws_elasticache_cluster" "stock" {
  cluster_id           = "stocks-stock"
  engine               = "memcached"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.6"
  port                 = 11211
}

data "aws_ecr_image" "stock" {
  repository_name = data.terraform_remote_state.personal_aws.outputs.ecr_personal_test_repo_name
  image_tag       = "stock"
}

resource "aws_iam_role" "stock" {
  name = "stocks_stock"

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

resource "aws_iam_role_policy_attachment" "stock_basic_exec" {
  role       = aws_iam_role.stock.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "stock_ec2" {
  name        = "stocks_stock_ec2"
  description = "IAM policy for EC2"

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

resource "aws_iam_role_policy_attachment" "stock_ec2" {
  role       = aws_iam_role.stock.name
  policy_arn = aws_iam_policy.stock_ec2.arn
}

resource "aws_iam_policy" "stock_secrets" {
  name        = "stocks_stock_secrets"
  description = "IAM policy for accessing secrets in AWS Secrets Manager"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue"
        ],
        "Resource" : [
          aws_secretsmanager_secret.third_party_api.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "stock_secrets" {
  role       = aws_iam_role.stock.name
  policy_arn = aws_iam_policy.stock_secrets.arn
}

resource "aws_security_group" "stock_lambda" {
  name        = "stock-lambda-sg"
  description = "Security group for stock Lambda."

  tags = {
    Name = "stock-lambda-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "stock_lambda" {
  security_group_id = aws_security_group.stock_lambda.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_lambda_function" "stock" {
  function_name = "stock"
  role          = aws_iam_role.stock.arn
  package_type  = "Image"
  image_uri     = data.aws_ecr_image.stock.image_uri
  memory_size   = 128
  timeout       = 60

  vpc_config {
    subnet_ids         = data.aws_subnets.private_subnets.ids
    security_group_ids = [aws_security_group.stock_lambda.id]
  }

  environment {
    variables = {
      THIRD_PARTY_API_KEY_ARN = aws_secretsmanager_secret.third_party_api.arn
      MEMCACHED_ENDPOINT = aws_elasticache_cluster.stock.cluster_address
    }
  }
}

resource "aws_apigatewayv2_integration" "stock" {
  api_id                 = aws_apigatewayv2_api.stocks.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.stock.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "stock" {
  api_id    = aws_apigatewayv2_api.stocks.id
  route_key = "GET /stock"

  target = "integrations/${aws_apigatewayv2_integration.stock.id}"
}

resource "aws_apigatewayv2_stage" "stock" {
  api_id      = aws_apigatewayv2_api.stocks.id
  name        = "dev"
  auto_deploy = true

  route_settings {
    route_key              = "GET /stock"
    throttling_rate_limit  = 1 # RPS
    throttling_burst_limit = 1 # RPS
  }
}

resource "aws_lambda_permission" "stock" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stock.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.stocks.execution_arn}/*/*"
}

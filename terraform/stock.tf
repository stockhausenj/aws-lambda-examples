data "aws_ecr_image" "stock" {
  repository_name = data.terraform_remote_state.personal_aws.outputs.ecr_personal_test_repo_name
  image_tag       = "stock"
}

resource "aws_iam_role" "stock" {
  name = "stocks_stock"

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

resource "aws_iam_role_policy_attachment" "stock_basic_exec" {
  role       = aws_iam_role.stock.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "stock" {
  name        = "stocks_stock"
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
          aws_secretsmanager_secret.third_party_api.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "stock" {
  role       = aws_iam_role.stock.name
  policy_arn = aws_iam_policy.stock.arn
}

resource "aws_lambda_function" "stock" {
  function_name    = "stock"
  role             = aws_iam_role.stock.arn
  package_type     = "Image"
  image_uri        = data.aws_ecr_image.stock.image_uri
  memory_size      = 128
  timeout          = 60

  environment {
    variables = {
      THIRD_PARTY_API_KEY_ARN = aws_secretsmanager_secret.third_party_api.arn
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

  route_settings = {
    throttling_rate_limit = 1 # RPS
  }
}

resource "aws_lambda_permission" "stock" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stock.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.stocks.execution_arn}/*/*"
}

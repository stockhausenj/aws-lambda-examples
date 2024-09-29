data "aws_ecr_image" "third_party_api_sync" {
  repository_name = data.terraform_remote_state.personal_aws.outputs.ecr_personal_test_repo_name
  image_tag       = "third-party-sync"
}

resource "aws_iam_role" "third_party_api_sync" {
  name = "stocks_third_party_api_sync"

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

resource "aws_iam_role_policy_attachment" "third_party_api_sync_basic_exec" {
  role       = aws_iam_role.third_party_api_sync.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "third_party_api_sync" {
  name        = "stocks_third_party_api_sync"
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

resource "aws_iam_role_policy_attachment" "third_party_api_sync" {
  role       = aws_iam_role.third_party_api_sync.name
  policy_arn = aws_iam_policy.third_party_api_sync.arn
}

resource "aws_lambda_function" "third_party_api_sync" {
  function_name    = "stocks_third_party_api_sync"
  role             = aws_iam_role.third_party_api_sync.arn
  package_type     = "Image"
  image_uri        = data.aws_ecr_image.third_party_api_sync.image_uri
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

resource "aws_cloudwatch_event_rule" "third_party_api_sync" {
  name                = "third_party_api_sync_cron_schedule"
  description         = "Run Lambda every hour Monday-Friday"
  schedule_expression = "cron(0 * ? * 2-6 *)"  # Cron expression for Monday-Friday, every hour
}

resource "aws_lambda_permission" "cloudwatch_third_party_api_sync" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.third_party_api_sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.third_party_api_sync.arn
}

resource "aws_cloudwatch_event_target" "third_party_api_sync" {
  rule      = aws_cloudwatch_event_rule.third_party_api_sync.name
  target_id = "lambda_target"
  arn       = aws_lambda_function.third_party_api_sync.arn
}

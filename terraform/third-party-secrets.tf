resource "aws_secretsmanager_secret" "third_party_api" {
  name = "third_party_api"
}

resource "aws_secretsmanager_secret_version" "third_party_api_key" {
  secret_id     = aws_secretsmanager_secret.third_party_api.id
  secret_string = var.third_party_api_key
}

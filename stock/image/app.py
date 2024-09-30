import json
import os

import boto3
import requests
from botocore.exceptions import ClientError


def get_secret(secret_name):
    client = boto3.client("secretsmanager")
    try:
        response = client.get_secret_value(SecretId=secret_name)
        if "SecretString" in response:
            return response["SecretString"]
        else:
            return response["SecretBinary"]
    except ClientError as e:
        print(f"Error retrieving secret {secret_name}: {e}")
        raise e


def handler(event, context):
    alpha_vantage_api_key = get_secret(os.getenv("THIRD_PARTY_API_KEY_ARN"))
    symbol = event.get("queryStringParameters", {}).get("symbol", None)

    if not symbol:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Symbol parameter is required"}),
            "headers": {"Content-Type": "application/json"},
        }

    url = f"https://www.alphavantage.co/query?function=OVERVIEW&symbol={symbol}&apikey={alpha_vantage_api_key}"
    response = requests.get(url)

    if response.status_code != 200:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Error fetching stock data"}),
            "headers": {"Content-Type": "application/json"},
        }

    data = response.json()

    if "Error Message" in data:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": f"Stock symbol {symbol} not found"}),
            "headers": {"Content-Type": "application/json"},
        }

    return {
        "statusCode": 200,
        "body": json.dumps(data),
        "headers": {"Content-Type": "application/json"},
    }

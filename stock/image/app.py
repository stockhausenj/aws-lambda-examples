import json
import os

# import boto3
import pylibmc
import requests

# from botocore.config import Config
# from botocore.exceptions import ClientError

"""
def get_secret(secret_name):
    boto_config = Config(region_name="us-east-1")
    client = boto3.client("secretsmanager", config=boto_config)
    try:
        response = client.get_secret_value(SecretId=secret_name)
        if "SecretString" in response:
            return response["SecretString"]
        else:
            return response["SecretBinary"]
    except ClientError as e:
        print(f"Error retrieving secret {secret_name}: {e}")
        raise e
"""


def api_request(symbol):
    alpha_vantage_api_key = os.getenv("THIRD_PARTY_API_KEY_ARN")
    url = f"https://www.alphavantage.co/query?function=OVERVIEW&symbol={symbol}&apikey={alpha_vantage_api_key}"
    response = requests.get(url)
    if response.status_code == 200:
        return response.json(), 200
    elif response.status_code == 404:
        return {}, 404
    else:
        return {}, 500


def handler(event, context):
    symbol = event.get("queryStringParameters", {}).get("symbol", None)

    if not symbol:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Symbol parameter is required"}),
            "headers": {"Content-Type": "application/json"},
        }

    memcached_client = pylibmc.Client([os.getenv("MEMCACHED_ENDPOINT")], binary=True)
    cached_response = memcached_client.get(symbol)

    symbol_data = {}

    if cached_response:
        print("Cache hit: Returning cached response")
        symbol_data = json.loads((cached_response))
    else:
        print("Cache miss: Fetching from API")
        symbol_data, response_code = api_request(symbol)
        if response_code == 200:
            print(f"Adding to cache: {symbol_data}")
            memcached_client.set(symbol, json.dumps(symbol_data), time=3600)
            print(f"Added to cache: {symbol_data}")
        elif response_code == 404:
            return {
                "statusCode": 404,
                "body": json.dumps({"error": f"Stock symbol {symbol} not found"}),
                "headers": {"Content-Type": "application/json"},
            }
        else:
            return {
                "statusCode": 500,
                "body": json.dumps({"error": "Error fetching stock data"}),
                "headers": {"Content-Type": "application/json"},
            }

    return {
        "statusCode": 200,
        "body": json.dumps(symbol_data),
        "headers": {"Content-Type": "application/json"},
    }

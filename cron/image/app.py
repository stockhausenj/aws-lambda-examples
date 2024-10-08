import json
import os
from datetime import datetime

import boto3
import psycopg2
import requests
from botocore.exceptions import ClientError

STOCK_SYMBOLS = [
    "AAPL",
    "AI",
    "AMD",
    "AMZN",
    "DNA",
    "INTC",
    "LCID",
    "META",
    "MSFT",
    "MU",
    "NET",
    "NVDA",
    "OKTA",
    "RIVN",
    "SOFI",
    "TSLA",
    "UBER",
]


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

    conn = psycopg2.connect(
        host=os.getenv("RDS_HOST"),
        database=os.getenv("RDS_DATABASE"),
        user=os.getenv("RDS_USER"),
        password=get_secret(os.getenv("RDS_PASSWORD_ARN")),
    )

    current_timestamp = datetime.utcnow()
    for symbol in STOCK_SYMBOLS:
        url = f"https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol={symbol}&apikey={alpha_vantage_api_key}"
        response = requests.get(url)
        data = response.json()

        if "Time Series (Daily)" in data:
            # Parse the stock price (latest available data)
            latest_timestamp = list(data["Time Series (Daily)"].keys())[0]
            latest_price = data["Time Series (Daily)"][latest_timestamp]["4. close"]

            with conn.cursor() as cur:
                cur.execute(
                    """
          INSERT INTO stocks (symbol, price, timestamp)
          VALUES (%s, %s, %s)
          """,
                    (symbol, latest_price, current_timestamp),
                )
                print(f"Inserted {symbol}: {latest_price} at {current_timestamp}")

        else:
            print(f"No data found for {symbol}. API response: {data}")

    conn.commit()

    return {"statusCode": 200, "body": json.dumps("Stock price updated successfully!")}

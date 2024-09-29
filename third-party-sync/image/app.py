import boto3
from botocore.exceptions import ClientError
import json
import os
import psycopg2
import requests

from datetime import datetime


STOCK_SYMBOLS = ['AAPL', 'AI', 'AMD', 'AMZN', 'DNA', 'INTC', 'LCID', 'META', 'MSFT', 'MU', 'NET', 'NVDA', 'OKTA', 'RIVN', 'SOFI', 'TSLA', 'UBER']

def get_secret(secret_name):
    client = boto3.client('secretsmanager')
    try:
        response = client.get_secret_value(SecretId=secret_name)
        if 'SecretString' in response:
            return response['SecretString']
        else:
            return response['SecretBinary']
    except ClientError as e:
        print(f"Error retrieving secret {secret_name}: {e}")
        raise e

def handler(event, context):
  alpha_vantage_api_key = get_secret('third_party_api_key')

  conn = psycopg2.connect(
    host=os.getenv('RDS_HOST'),
    database=os.getenv('RDS_DATABASE'),
    user=os.getenv('RDS_USER'),
    password=get_secret('db_access')
	)

  current_timestamp = datetime.utcnow()
  for symbol in STOCK_SYMBOLS:
    url = f'https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&symbol={symbol}&interval=1min&apikey={alpha_vantage_api_key}'
    response = requests.get(url)
    data = response.json()

    if "Time Series (1min)" in data:
      # Parse the stock price (latest available data)
      latest_timestamp = list(data['Time Series (1min)'].keys())[0]
      latest_price = data['Time Series (1min)'][latest_timestamp]['1. open']

      with conn.cursor() as cur:
        cur.execute("""
          INSERT INTO stocks (symbol, price, timestamp)
          VALUES (%s, %s, %s)
          """, (symbol, latest_price, current_timestamp))
        print(f"Inserted {symbol}: {latest_price} at {current_timestamp}")

    else:
        print(f"No data found for {symbol}. API response: {data}")

  conn.commit()

  return {
      'statusCode': 200,
      'body': json.dumps('Stock price updated successfully!')
  }

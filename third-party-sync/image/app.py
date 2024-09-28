import json
import os
import psycopg2
import requests

from datetime import datetime


conn = psycopg2.connect(
  host=os.getenv('RDS_HOST'),
  database=os.getenv('RDS_DATABASE'),
  user=os.getenv('RDS_USER'),
  password=os.getenv('RDS_PASSWORD')
)

ALPHA_VANTAGE_API_KEY = os.getenv('ALPHA_VANTAGE_API_KEY')
STOCK_SYMBOLS = ['IBM', 'AAPL', 'GOOGL']  # Add more symbols as needed

def handler(event, context):
  current_timestamp = datetime.utcnow()
  for symbol in STOCK_SYMBOLS:
    url = f'https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&symbol={symbol}&interval=1min&apikey={ALPHA_VANTAGE_API_KEY}'
    response = requests.get(url)
    data = response.json()

    # Check if the response contains the expected data
    if "Time Series (1min)" in data:
      # Step 2: Parse the stock price (latest available data)
      latest_timestamp = list(data['Time Series (1min)'].keys())[0]
      latest_price = data['Time Series (1min)'][latest_timestamp]['1. open']

      # Step 3: Insert or update the stock price in the PostgreSQL database
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

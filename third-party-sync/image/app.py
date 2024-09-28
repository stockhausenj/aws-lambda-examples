import json
import requests
import psycopg2
import os
from datetime import datetime

# Set up PostgreSQL connection
conn = psycopg2.connect(
    host=os.getenv('RDS_HOST'),
    database=os.getenv('RDS_DATABASE'),
    user=os.getenv('RDS_USER'),
    password=os.getenv('RDS_PASSWORD')
)

ALPHA_VANTAGE_API_KEY = os.getenv('ALPHA_VANTAGE_API_KEY')
SYMBOL = 'IBM'  # Example stock symbol, you can change this

def lambda_handler(event, context):
    # Step 1: Fetch stock price data from the Alpha Vantage API
    url = f'https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&symbol={SYMBOL}&interval=1min&apikey={ALPHA_VANTAGE_API_KEY}'
    response = requests.get(url)
    data = response.json()

    # Step 2: Parse the stock price (latest available data)
    latest_timestamp = list(data['Time Series (1min)'].keys())[0]
    latest_price = data['Time Series (1min)'][latest_timestamp]['1. open']

    # Step 3: Insert or update the stock price in the PostgreSQL database
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO stock_prices (symbol, price, timestamp)
            VALUES (%s, %s, %s)
            """, (SYMBOL, latest_price, datetime.strptime(latest_timestamp, '%Y-%m-%d %H:%M:%S')))

    conn.commit()

    return {
        'statusCode': 200,
        'body': json.dumps('Stock price updated successfully!')
    }

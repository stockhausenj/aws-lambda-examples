import boto3
from botocore.exceptions import ClientError
import json
import os
import pymemcache
import psycopg2


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
  cache_client = pymemcache.Client(('memcached-endpoint', 11211))

  

  conn = psycopg2.connect(
    host=os.getenv('RDS_HOST'),
    database=os.getenv('RDS_DATABASE'),
    user=os.getenv('RDS_USER'),
    password=get_secret(os.getenv('RDS_PASSWORD_ARN'))
	)

  #with conn.cursor() as cur:

  conn.commit()

  return {
      'statusCode': 200,
      'body': json.dumps('Stock price updated successfully!')
  }

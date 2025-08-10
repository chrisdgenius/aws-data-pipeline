import json
import random
import boto3
from datetime import datetime, timedelta
from faker import Faker
import argparse

fake = Faker()

def generate_transaction_data(num_records=1000, start_date=None, end_date=None):
    """Generate sample transaction data"""
    if not start_date:
        start_date = datetime.now() - timedelta(days=30)
    if not end_date:
        end_date = datetime.now()
    
    transactions = []
    customer_ids = [f"cust_{i:06d}" for i in range(1, 201)]  # 200 customers
    
    for i in range(num_records):
        transaction = {
            "transaction_id": f"txn_{i:08d}",
            "customer_id": random.choice(customer_ids),
            "amount": round(random.uniform(10, 5000), 2),
            "transaction_date": fake.date_time_between(
                start_date=start_date, 
                end_date=end_date
            ).strftime('%Y-%m-%d %H:%M:%S'),
            "transaction_type": random.choice(["purchase", "refund", "adjustment"]),
            "merchant_id": f"merchant_{random.randint(1, 50):03d}",
            "payment_method": random.choice(["credit_card", "debit_card", "paypal", "bank_transfer"]),
            "currency": "USD",
            "status": random.choice(["completed", "pending", "failed"]),
            "category": random.choice(["electronics", "clothing", "food", "books", "home"])
        }
        transactions.append(transaction)
    
    return transactions

def upload_to_s3(data, bucket_name, key_prefix):
    """Upload data to S3"""
    s3_client = boto3.client('s3')
    
    # Create files in batches to simulate incremental loading
    batch_size = 100
    for i in range(0, len(data), batch_size):
        batch = data[i:i + batch_size]
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        key = f"{key_prefix}/batch_{i//batch_size}_{timestamp}.json"
        
        # Convert to JSONL format
        jsonl_data = '\n'.join([json.dumps(record) for record in batch])
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=jsonl_data,
            ContentType='application/json'
        )
        
        print(f"Uploaded batch {i//batch_size + 1} to s3://{bucket_name}/{key}")

def main():
    parser = argparse.ArgumentParser(description='Generate test data for data pipeline')
    parser.add_argument('--records', type=int, default=1000, help='Number of records to generate')
    parser.add_argument('--bucket', required=True, help='S3 bucket name')
    parser.add_argument('--prefix', default='raw/transactions', help='S3 key prefix')
    
    args = parser.parse_args()
    
    # Generate data
    print(f"Generating {args.records} transaction records...")
    transactions = generate_transaction_data(args.records)
    
    # Upload to S3
    print(f"Uploading to S3 bucket: {args.bucket}")
    upload_to_s3(transactions, args.bucket, args.prefix)
    
    print("Data generation completed!")

if __name__ == "__main__":
    main()
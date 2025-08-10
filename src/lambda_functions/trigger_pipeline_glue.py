import json
import boto3
import logging
from datetime import datetime

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to trigger the data pipeline
    """
    glue_client = boto3.client('glue')
    
    try:
        # Get job name from environment variable
        job_name = os.environ.get('GLUE_JOB_NAME')
        
        if not job_name:
            raise ValueError("GLUE_JOB_NAME environment variable not set")
        
        # Start Glue job
        response = glue_client.start_job_run(
            JobName=job_name,
            Arguments={
                '--execution-date': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            }
        )
        
        job_run_id = response['JobRunId']
        logger.info(f"Started Glue job {job_name} with run ID: {job_run_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully triggered pipeline job: {job_name}',
                'job_run_id': job_run_id
            })
        }
       # End Glue job
    except Exception as e:
        logger.error(f"Error triggering pipeline: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
     # End Glue job
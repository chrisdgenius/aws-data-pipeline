import json
import boto3
import os
import logging
from datetime import datetime

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to trigger the data pipeline via Step Functions
    """
    stepfunctions_client = boto3.client('stepfunctions')
    
    try:
        # Get Step Function ARN from environment variable
        step_function_arn = os.environ.get('STEP_FUNCTION_ARN')
        
        if not step_function_arn:
            raise ValueError("STEP_FUNCTION_ARN environment variable not set")
        
        # Prepare execution input with timestamp and any event data
        execution_input = {
            'execution_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'trigger_event': event,
            'environment': os.environ.get('ENVIRONMENT', 'unknown')
        }
        
        # Generate unique execution name with timestamp
        execution_name = f"pipeline-execution-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        
        # Start Step Function execution
        response = stepfunctions_client.start_execution(
            stateMachineArn=step_function_arn,
            name=execution_name,
            input=json.dumps(execution_input)
        )
        
        execution_arn = response['executionArn']
        logger.info(f"Started Step Function execution: {execution_name}")
        logger.info(f"Execution ARN: {execution_arn}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully triggered data pipeline',
                'execution_name': execution_name,
                'execution_arn': execution_arn,
                'step_function_arn': step_function_arn
            })
        }
        
    except Exception as e:
        logger.error(f"Error triggering pipeline: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'step_function_arn': os.environ.get('STEP_FUNCTION_ARN', 'not_set')
            })
        }
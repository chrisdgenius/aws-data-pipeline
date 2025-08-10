#!/bin/bash

set -e

# Configuration
PROJECT_NAME="aws-data-pipeline"
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-1}

echo "Triggering $PROJECT_NAME pipeline in $ENVIRONMENT environment"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "Error: AWS CLI not configured. Please run 'aws configure'"
    exit 1
fi

# Construct Lambda function name
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-trigger-pipeline-$ENVIRONMENT"

# Check if Lambda function exists
if ! aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME > /dev/null 2>&1; then
    echo "Error: Lambda function '$LAMBDA_FUNCTION_NAME' not found"
    echo "Make sure you've deployed the infrastructure first"
    exit 1
fi

echo "Found Lambda function: $LAMBDA_FUNCTION_NAME"

# Trigger the pipeline
echo "Manually triggering the pipeline..."

# Create payload and encode it properly
PAYLOAD='{"test": true, "trigger_source": "manual_script", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
echo "Payload: $PAYLOAD"

aws lambda invoke \
    --function-name $LAMBDA_FUNCTION_NAME \
    --cli-binary-format raw-in-base64-out \
    --payload "$PAYLOAD" \
    response.json

# Check if the invocation was successful
if [ $? -eq 0 ]; then
    echo "✅ Lambda function invoked successfully!"
    echo
    echo "Response:"
    if command -v jq &> /dev/null; then
        cat response.json | jq '.'
    else
        cat response.json
    fi
    echo
    
    # Parse the Lambda response to get execution details
    if command -v jq &> /dev/null; then
        LAMBDA_RESPONSE=$(cat response.json | jq -r '.Payload' 2>/dev/null || echo "{}")
        if [[ $LAMBDA_RESPONSE != "{}" && $LAMBDA_RESPONSE != "null" ]]; then
            echo "Lambda execution details:"
            echo $LAMBDA_RESPONSE | jq '.' 2>/dev/null || echo $LAMBDA_RESPONSE
            echo
        fi
    fi
    
    echo "🔍 Monitor pipeline execution:"
    echo "Step Functions Console: https://console.aws.amazon.com/states/home?region=$AWS_REGION#/statemachines"
    echo "CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#logsV2:log-groups"
    echo
    echo "📊 To check execution status:"
    echo "aws stepfunctions list-executions --state-machine-arn \$(terraform output -raw step_function_arn) --max-items 5"
    
    # Clean up response file
    rm -f response.json
    
    echo
    echo "🚀 Pipeline trigger completed successfully!"
else
    echo "❌ Failed to invoke Lambda function"
    echo "Response file contents:"
    cat response.json 2>/dev/null || echo "No response file generated"
    rm -f response.json
    exit 1
fi
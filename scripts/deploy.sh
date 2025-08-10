#!/bin/bash

set -e

# Configuration
PROJECT_NAME="aws-data-pipeline"
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-1}

echo "Deploying $PROJECT_NAME to $ENVIRONMENT environment in $AWS_REGION"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "Error: AWS CLI not configured. Please run 'aws configure'"
    exit 1
fi

# Package and upload Lambda functions
echo "Packaging Lambda functions..."
cd src/lambda_functions
zip -r trigger_pipeline.zip trigger_pipeline.py

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform not installed"
    exit 1
fi

# Navigate to terraform directory
cd ../../infrastructure/terraform

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# PHASE 1: Deploy infrastructure WITHOUT triggers
echo "Phase 1: Deploying infrastructure without triggers..."
terraform plan -var="environment=$ENVIRONMENT" -var="aws_region=$AWS_REGION" -var="enable_pipeline_triggers=false"
terraform apply -auto-approve -var="environment=$ENVIRONMENT" -var="aws_region=$AWS_REGION" -var="enable_pipeline_triggers=false"

# Get bucket names from terraform output
RAW_BUCKET=$(terraform output -raw raw_data_bucket)
PROCESSED_BUCKET=$(terraform output -raw processed_data_bucket)
SCRIPTS_BUCKET=$(terraform output -raw glue_scripts_bucket)

echo "Phase 1 completed - Infrastructure deployed without triggers"
echo "Raw data bucket: $RAW_BUCKET"
echo "Processed data bucket: $PROCESSED_BUCKET"
echo "Scripts bucket: $SCRIPTS_BUCKET"

# Update Lambda function with latest code
echo "Updating Lambda function code..."
cd ../../src/lambda_functions
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-trigger-pipeline-$ENVIRONMENT"
aws lambda update-function-code \
    --function-name $LAMBDA_FUNCTION_NAME \
   --zip-file fileb://trigger_pipeline.zip \
   --no-cli-pager \
   --output json | cat

# Check the exit status of the AWS CLI command
AWS_CLI_EXIT_CODE=${PIPESTATUS[0]}

if [ $AWS_CLI_EXIT_CODE -eq 0 ]; then
    echo "Successfully updated Lambda function: $LAMBDA_FUNCTION_NAME"
else
    echo "Failed to update Lambda function: $LAMBDA_FUNCTION_NAME"
    echo "AWS CLI exit code: $AWS_CLI_EXIT_CODE"
    exit 1
fi

# Generate test data
echo "Generating test data..."
cd ../../scripts
python3 generate_test_data.py --records 1000 --bucket $RAW_BUCKET

echo "Test data generation completed!"

# PHASE 2: Enable triggers now that everything is ready
echo "Phase 2: Enabling S3 triggers..."
cd ../infrastructure/terraform
terraform apply -auto-approve -var="environment=$ENVIRONMENT" -var="aws_region=$AWS_REGION" -var="enable_pipeline_triggers=true"

echo "Deployment completed successfully!"
echo "Pipeline triggers are now active and will process new files in the incoming/ folder"
echo "You can also manually trigger the pipeline by invoking: $LAMBDA_FUNCTION_NAME"







# Optional: Manually trigger the pipeline to test everything works
read -p "Do you want to manually trigger the pipeline now to test it? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Manually triggering the pipeline..."
    


        aws lambda invoke \
    --function-name $LAMBDA_FUNCTION_NAME \
    --cli-binary-format raw-in-base64-out \
    --payload "$PAYLOAD" \
    response.json

    
    # Check if the invocation was successful
    if [ $? -eq 0 ]; then
        echo "Lambda function invoked successfully!"
        echo "Response:"
        cat response.json | jq '.' 2>/dev/null || cat response.json
        echo
        echo "Check the Step Functions console to monitor pipeline execution:"
        echo "https://console.aws.amazon.com/states/home?region=$AWS_REGION#/statemachines"
        
        # Clean up response file
        rm -f response.json
    else
        echo "Failed to invoke Lambda function"
        exit 1
    fi
else
    echo "Skipping manual trigger. You can trigger it later with:"
    echo "aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --payload '{}' response.json"
fi
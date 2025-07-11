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

# Plan deployment
echo "Planning Terraform deployment..."
terraform plan -var="environment=$ENVIRONMENT" -var="aws_region=$AWS_REGION"

# Apply deployment
echo "Applying Terraform deployment..."
terraform apply -auto-approve -var="environment=$ENVIRONMENT" -var="aws_region=$AWS_REGION"

# Get bucket names from terraform output
RAW_BUCKET=$(terraform output -raw raw_data_bucket)
PROCESSED_BUCKET=$(terraform output -raw processed_data_bucket)
SCRIPTS_BUCKET=$(terraform output -raw glue_scripts_bucket)


# Remove Lambda function zip file
# echo "Removing Lambda function zip file..."
# cd ../../src/lambda_functions
# rm trigger_pipeline.zip

# echo "Zip file removal Done."

echo "Deployment completed successfully!"
echo "Raw data bucket: $RAW_BUCKET"
echo "Processed data bucket: $PROCESSED_BUCKET"
echo "Scripts bucket: $SCRIPTS_BUCKET"


# Update Lambda function
cd ../../src/lambda_functions
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-trigger-pipeline-$ENVIRONMENT"
aws lambda update-function-code \
    --function-name $LAMBDA_FUNCTION_NAME \
   --zip-file fileb://trigger_pipeline.zip \
   --no-cli-pager \
   --output json | cat
 # Check the exit status of the AWS CLI command
AWS_CLI_EXIT_CODE=${PIPESTATUS[0]} # PIPESTATUS[0] holds the exit code of the first command in the pipe

# Check the exit status of the AWS CLI command
if [ $AWS_CLI_EXIT_CODE -eq 0 ]; then
    echo "Successfully updated Lambda function: $LAMBDA_FUNCTION_NAME"
else
    echo "Failed to update Lambda function: $LAMBDA_FUNCTION_NAME"
    echo "AWS CLI exit code: $AWS_CLI_EXIT_CODE"
fi

echo "Lambda functions updated successfully!"

# Generate test data
echo "Generating test data..."
cd ../../scripts
python3 generate_test_data.py --records 1000 --bucket $RAW_BUCKET

echo "Deployment completed successfully!"
echo "You can now trigger the pipeline by invoking the Lambda function: $LAMBDA_FUNCTION_NAME"

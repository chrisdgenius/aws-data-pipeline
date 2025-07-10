#!/bin/bash

set -e

# Configuration
PROJECT_NAME="data-pipeline"
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-1}

echo "Deploying $PROJECT_NAME to $ENVIRONMENT environment in $AWS_REGION"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "Error: AWS CLI not configured. Please run 'aws configure'"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform not installed"
    exit 1
fi

# Navigate to terraform directory
cd infrastructure/terraform

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

echo "Deployment completed successfully!"
echo "Raw data bucket: $RAW_BUCKET"
echo "Processed data bucket: $PROCESSED_BUCKET"
echo "Scripts bucket: $SCRIPTS_BUCKET"


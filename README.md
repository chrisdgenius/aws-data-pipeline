# aws-data-pipeline
Step 1: AWS CLI
1. Install aws cli
brew install awscli
2. confirm the installation
aws --version
3. Configure access to aws
aws configure
input your key id, secret and region.
4. Test to ensure connection is good by listing all buckets
aws s3 ls

Step 2: Terraform
#  install Terraform
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
2. Check installation
terraform -v

Step 3: Install vs code extensions like aws toolkit, terraform, gitlens, yaml,json ans thunder client or rest client

CREATE THE PROJECT STRUCTURE

Step 1: Create parent directories


# Create the folder structure
mkdir -p infrastructure/terraform
mkdir -p src/glue_jobs
mkdir -p src/lambda_functions
mkdir -p src/step_functions
mkdir -p tests/{unit,integration,data_quality}
mkdir -p monitoring/{cloudwatch_dashboards,alerts}
mkdir -p scripts
mkdir -p .github/workflows
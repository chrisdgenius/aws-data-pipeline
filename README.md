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

# Configure your github for quick commit
git config --global user.name "chrisdgenius" 
git config --global user.email okonta.christian@yahoo.com
git init
git add .
git commit -m "project structure"
git push -u origin main
git remote -v
git remote add origin https://github.com/chrisdgenius/aws-data-pipeline.git


#write your terraform code to deploy your infrastructures
cd to the terraform location to run your terraform
terraform init
terrafor plan
terraform apply
terraform destroy



make sure the script is executable
chmod +x ./scripts/deploy.sh

Run the script
ENSURE THAT YOU ARE IN THE ROOT DIRECTORY BEFORE RUNNING THE SCRIPT SINCE IT HAVE TO NAVIGATE TO DIFFERENT PATHS
./scripts/deploy.sh dev us-east-1  

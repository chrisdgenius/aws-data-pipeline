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
git branch
git remote add origin https://github.com/chrisdgenius/aws-data-pipeline.git
git branch dev  
git checkout dev  
git add .  
git commit -m " Pushing to dev branch "
git push -u origin dev   

# write your terraform code to deploy your infrastructures
cd to the terraform location to run your terraform
terraform init
terrafor plan
terraform apply
terraform destroy



# ake sure the script is executable
chmod +x ./scripts/deploy.sh

# Run the script
ENSURE THAT YOU ARE IN THE ROOT DIRECTORY BEFORE RUNNING THE SCRIPT SINCE IT HAVE TO NAVIGATE TO DIFFERENT PATHS
./scripts/deploy.sh dev us-east-1  

Note:
If a zip file exist, terraform will not upload it.
so always use the copy command.


# Install virtual environment to run python packages
brew install python@3.11

# 1. Create a virtual environment (in a folder called .venv)
python3 -m venv venv

# 2. Activate the virtual environment
source venv/bin/activate
# Install required build tools, like setuptools, wheel, or build.
pip install --upgrade pip setuptools wheel build

# 3. Install your packages
pip install -r requirements.txt
# Deactivate anytime
deactivate

# Correcting python version
brew install python@3.11
/opt/homebrew/Cellar/python@3.11/3.11.13/bin/python3.11 --version

echo 'export PATH="/opt/homebrew/Cellar/python@3.11/3.11.13/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

deactivate
rm -rf venv
# Create new python environment
/opt/homebrew/Cellar/python@3.11/3.11.13/bin/python3.11 -m venv venv
# this will create a new environment with your specified python version
source venv/bin/activate

pip install -r requirements.txt


# Check status of glue job
aws glue get-job-runs --job-name aws-data-pipeline-bronze-to-silver-dev
# View Logs
aws logs tail /aws-glue/jobs/aws-data-pipeline-dev --follow

# import file back to Terraform state 
terraform import aws_cloudwatch_log_group.glue_logs1 /aws-glue/jobs/aws-data-pipeline-dev


# Manual trigger
./scripts/trigger.sh dev us-east-1


# Some issues encountered and how I solved them.
1. The lamda function was being triggered immediately the s3 bucket is created. This was affecting the creation of the cloudwatch log group as the service was being used. This result in conflict.
I have to use a trigger variable to disable the lamda function until all the infrastructures are created before reactivating it.
The solution implies a two phase deployment of the terraform inftrastructure.
Phase one with trigger set to false and phase two with the trigger set to true. The trigger variable is defined in the variable.tf and reference in the notification from bucket creations.
2. Another issue was that the step function was intiated immediately after deployment.
This was because the rate was set to 30 days in the cloudwatch event rule. This implies that the functions run immediatedly and in the next 30 days, so once deployed, it runs and wait for the next 30 days or a trigger usually from the lambda function or a manual trigger.
I have to also use same trigger variable to disable the lamda function until all the infrastructures are created before reactivating it.
The solution implies a two phase deployment of the terraform inftrastructure.
Phase one with trigger set to false and phase two with the trigger set to true. The trigger variable is defined in the variable.tf and reference in the notification from bucket creations.
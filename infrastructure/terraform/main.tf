terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# S3 Buckets
resource "aws_s3_bucket" "raw_data" {
  bucket = "${var.project_name}-raw-data-${var.environment}"
  
  tags = {
    Name        = "Raw Data Bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "processed_data" {
  bucket = "${var.project_name}-processed-data-${var.environment}"
  
  tags = {
    Name        = "Processed Data Bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${var.project_name}-glue-scripts-${var.environment}"
  
  tags = {
    Name        = "Glue Scripts Bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "raw_data_versioning" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "processed_data_versioning" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data_encryption" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data_encryption" {
  bucket = aws_s3_bucket.processed_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role for Glue
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "${var.project_name}-glue-s3-policy-${var.environment}"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      }
    ]
  })
}

# Glue Database
resource "aws_glue_catalog_database" "data_lake" {
  name = "${var.project_name}_data_lake_${var.environment}"
  
  description = "Data lake database for ${var.project_name}"
}

# Upload a glue script bronze_to_silver.py to S3

resource "aws_s3_object" "bronze_to_silver_script_upload" {
  bucket = aws_s3_bucket.glue_scripts.bucket
  key    = "bronze_to_silver.py"
  source = "${path.module}/../../src/glue_jobs/bronze_to_silver.py"
  etag   = filemd5("${path.module}/../../src/glue_jobs/bronze_to_silver.py")
  content_type = "text/x-python"
}

# Upload a glue script src/glue_jobs/silver_to_gold.py to S3

resource "aws_s3_object" "silver_to_gold_script_upload" {
  bucket = aws_s3_bucket.glue_scripts.bucket
  key    = "silver_to_gold.py"
  source = "${path.module}/../../src/glue_jobs/silver_to_gold.py"
  etag   = filemd5("${path.module}/../../src/glue_jobs/silver_to_gold.py")
  content_type = "text/x-python"
}


# Glue Jobs
resource "aws_glue_job" "bronze_to_silver" {
  depends_on = [aws_s3_object.bronze_to_silver_script_upload]
  name     = "${var.project_name}-bronze-to-silver-${var.environment}"
  role_arn = aws_iam_role.glue_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--TempDir"                = "s3://${aws_s3_bucket.glue_scripts.bucket}/temp/"
    "--job-bookmark-option"    = "job-bookmark-enable"
    "--enable-metrics"         = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--raw-data-bucket"        = aws_s3_bucket.raw_data.bucket
    "--processed-data-bucket"  = aws_s3_bucket.processed_data.bucket
  }

  glue_version = "4.0"
  max_capacity = 2
  timeout      = 2880
}

resource "aws_glue_job" "silver_to_gold" {
  name     = "${var.project_name}-silver-to-gold-${var.environment}"
  role_arn = aws_iam_role.glue_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/silver_to_gold.py"
    python_version  = "3"
  }

  default_arguments = {
    "--TempDir"                = "s3://${aws_s3_bucket.glue_scripts.bucket}/temp/"
    "--job-bookmark-option"    = "job-bookmark-enable"
    "--enable-metrics"         = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--processed-data-bucket"  = aws_s3_bucket.processed_data.bucket
  }

  glue_version = "4.0"
  max_capacity = 2
  timeout      = 2880
}


# SECTION: STEP FUNCTION ORCHESTRATOR
#  The Step Function State Machine Resource ---


# IAM Role for Step Functions


# -----------------------------------------------------------------------------
# BEST PRACTICE: IAM ROLE & MANAGED POLICY FOR THE STEP FUNCTION
# -----------------------------------------------------------------------------

# 1. IAM Role for the Step Function to assume
resource "aws_iam_role" "step_function_role" {
  name = "${var.project_name}-step-function-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

# 2. A standalone, customer-managed IAM Policy with all required permissions
resource "aws_iam_policy" "sfn_orchestrator_policy" {
  name        = "${var.project_name}-sfn-policy-${var.environment}"
  description = "IAM policy for the main data pipeline Step Function orchestrator."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permissions for the Step Function to deliver logs to CloudWatch
      {
        Sid    = "AllowStepFunctionLoggingToCloudWatch"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      # Permissions for the Step Function to run Glue Jobs
      {
        Sid    = "AllowGlueJobExecution"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun"
        ]
        Resource = "*"
      },
      # Permission for the Step Function to publish to SNS
      {
        Sid      = "AllowSNSPublishing"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.pipeline_alerts.arn
      }
    ]
  })
}

# 3. An attachment that links the Role and the Policy together
resource "aws_iam_role_policy_attachment" "sfn_orchestrator_attachment" {
  role       = aws_iam_role.step_function_role.name
  policy_arn = aws_iam_policy.sfn_orchestrator_policy.arn
}

# Step Function State Machine


resource "aws_sfn_state_machine" "pipeline_orchestrator" {
  name     = "${var.project_name}-pipeline-orchestrator-${var.environment}"
  role_arn = aws_iam_role.step_function_role.arn # Ensure you have defined this role

  # --- Change: Use templatefile() instead of jsonencode() ---

  # We point Terraform to the external JSON file and provide the values for the placeholders.
  definition = templatefile("../../src/step_functions/pipeline_definition.json", {
    
    # Map Terraform resources to the ${placeholders} in the JSON file:
    bronze_job_name = aws_glue_job.bronze_to_silver.name
    silver_job_name = aws_glue_job.silver_to_gold.name
    sns_topic_arn   = aws_sns_topic.pipeline_alerts.arn
    project_name    = var.project_name
    # --- PARAMETERS ---
    raw_bucket_name       = aws_s3_bucket.raw_data.bucket
    processed_bucket_name = aws_s3_bucket.processed_data.bucket

  })

  # --- Logging configuration remains the same ---
  logging_configuration {
    # Assuming you have defined this CloudWatch Log Group
    log_destination        = "${aws_cloudwatch_log_group.step_function_logs.arn}:*" 
    include_execution_data = true
    level                  = "ERROR"
  }

  # To ensure the policy is attached before this resource is created
  depends_on = [
    aws_iam_role_policy_attachment.sfn_orchestrator_attachment
  ]


  # --- Tags remain the same ---
  tags = {
    Name        = "Data Pipeline State Machine"
    Environment = var.environment
    Project     = var.project_name
  }
}




# Lambda Function for Pipeline Trigger
# Lambda Function for Pipeline Trigger
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_step_function_policy" {
  name = "${var.project_name}-lambda-step-function-policy-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.pipeline_orchestrator.arn
        
      }
    ]
  })
}

resource "aws_lambda_function" "trigger_pipeline" {
  
  filename         = "${path.module}/../../src/lambda_functions/trigger_pipeline.zip"
  function_name    = "${var.project_name}-trigger-pipeline-${var.environment}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "trigger_pipeline.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      GLUE_JOB_NAME = aws_glue_job.bronze_to_silver.name
      STEP_FUNCTION_ARN = aws_sfn_state_machine.pipeline_orchestrator.arn
      ENVIRONMENT   = var.environment
    }
  }
}






# S3 Bucket notification to trigger Lambda when new files arrive
resource "aws_s3_bucket_notification" "raw_data_notification" {
  count  = var.enable_pipeline_triggers ? 1 : 0
  bucket = aws_s3_bucket.raw_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger_pipeline.arn
    events             = ["s3:ObjectCreated:*"]
    filter_prefix      = "incoming/"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger_pipeline.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "glue_logs" {
  name              = "/aws-glue/jobs/${var.project_name}-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "step_function_logs" {
  name              = "/aws/stepfunctions/${var.project_name}-${var.environment}"
  retention_in_days = 30
}

# SNS Topic for Alerts
resource "aws_sns_topic" "pipeline_alerts" {
  name = "${var.project_name}-pipeline-alerts-${var.environment}"
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "glue_job_failures" {
  alarm_name          = "${var.project_name}-glue-job-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors glue job failures"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]

  dimensions = {
    JobName = aws_glue_job.bronze_to_silver.name
  }
}

# CloudWatch Alarm for Step Function failures
resource "aws_cloudwatch_metric_alarm" "step_function_failures" {
  alarm_name          = "${var.project_name}-step-function-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors step function execution failures"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.pipeline_orchestrator.arn
  }
}

# EventBridge Rule for scheduled pipeline execution (optional)
resource "aws_cloudwatch_event_rule" "pipeline_schedule" {
  count               = var.enable_pipeline_triggers ? 1 : 0
  name                = "${var.project_name}-pipeline-schedule-${var.environment}"
  description         = "Trigger data pipeline on schedule"
  schedule_expression = "rate(30 days)"  # Run daily, adjust as needed
}

resource "aws_cloudwatch_event_target" "step_function_target" {
  count     = var.enable_pipeline_triggers ? 1 : 0
  rule      = aws_cloudwatch_event_rule.pipeline_schedule[0].name
  
  target_id = "StepFunctionTarget"
  arn       = aws_sfn_state_machine.pipeline_orchestrator.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}

# IAM Role for EventBridge
resource "aws_iam_role" "eventbridge_role" {
  name = "${var.project_name}-eventbridge-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_step_function_policy" {
  name = "${var.project_name}-eventbridge-step-function-policy-${var.environment}"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.pipeline_orchestrator.arn
      }
    ]
  })
}
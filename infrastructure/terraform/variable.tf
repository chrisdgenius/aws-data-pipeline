variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "data-pipeline"
  type        = string
  default     = "aws-data-pipeline"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "enable_pipeline_triggers" {
  description = "Enable S3 triggers for the pipeline"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "okonta.christian@gmail.com"
  type        = string
  default     = "okonta.christian@yahoo.com"
}
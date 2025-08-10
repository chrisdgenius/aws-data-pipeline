output "raw_data_bucket" {
  description = "Name of the raw data S3 bucket"
  value       = aws_s3_bucket.raw_data.bucket
}

output "processed_data_bucket" {
  description = "Name of the processed data S3 bucket"
  value       = aws_s3_bucket.processed_data.bucket
}
output "glue_scripts_bucket" {
  description = "Name of the Glue scripts S3 bucket"
  value       = aws_s3_bucket.glue_scripts.bucket
}

output "glue_database_name" {
  description = "Name of the Glue database"
  value       = aws_glue_catalog_database.data_lake.name
}

output "glue_job_bronze_to_silver" {
  description = "Name of the bronze to silver Glue job"
  value       = aws_glue_job.bronze_to_silver.name
}

output "glue_job_silver_to_gold" {
  description = "Name of the silver to gold Glue job"
  value       = aws_glue_job.silver_to_gold.name
}
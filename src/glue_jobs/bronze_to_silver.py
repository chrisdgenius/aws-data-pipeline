import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def validate_data_quality(df: DataFrame) -> DataFrame:
    """Validate data quality and filter out invalid records"""
    logger.info("Starting data quality validation")
    
    # Count initial records
    initial_count = df.count()
    logger.info(f"Initial record count: {initial_count}")
    
    # Remove duplicates based on transaction_id
    df_cleaned = df.dropDuplicates(["transaction_id"])
    
    # Remove records with null critical fields
    df_cleaned = df_cleaned.filter(
        col("transaction_id").isNotNull() & 
        col("customer_id").isNotNull() & 
        col("amount").isNotNull() &
        col("transaction_date").isNotNull()
    )
    
    # Remove records with invalid amounts
    df_cleaned = df_cleaned.filter(col("amount") > 0)
    
    # Add data quality flags
    df_cleaned = df_cleaned.withColumn("data_quality_score", lit(1.0))
    df_cleaned = df_cleaned.withColumn("processed_timestamp", current_timestamp())
    
    final_count = df_cleaned.count()
    logger.info(f"Final record count after cleaning: {final_count}")
    logger.info(f"Records removed: {initial_count - final_count}")
    
    return df_cleaned

def add_derived_columns(df: DataFrame) -> DataFrame:
    """Add derived columns for analytics"""
    logger.info("Adding derived columns")
    
    # Extract date components
    df = df.withColumn("year", year(col("transaction_date")))
    df = df.withColumn("month", month(col("transaction_date")))
    df = df.withColumn("day", dayofmonth(col("transaction_date")))
    df = df.withColumn("hour", hour(col("transaction_date")))
    
    # Categorize transaction amounts
    df = df.withColumn("amount_category", 
                      when(col("amount") < 100, "small")
                      .when(col("amount") < 1000, "medium")
                      .otherwise("large"))
    
    # Add transaction type based on amount patterns
    df = df.withColumn("transaction_type_derived",
                      when(col("amount") % 1 == 0, "whole_number")
                      .otherwise("decimal"))
    
    return df

def main():
    # Get job parameters
    args = getResolvedOptions(sys.argv, [
        'JOB_NAME',
        'raw-data-bucket',
        'processed-data-bucket'
    ])
    
    # Initialize Spark and Glue contexts
    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    
    logger.info(f"Starting job: {args['JOB_NAME']}")
    logger.info(f"Raw data bucket: {args['raw-data-bucket']}")
    logger.info(f"Processed data bucket: {args['processed-data-bucket']}")
    
    # Enable job bookmarking for incremental processing
    job.init(args['JOB_NAME'], args)
    
    try:
        # Read raw data from S3
        raw_data_path = f"s3://{args['raw-data-bucket']}/raw/transactions/"
        logger.info(f"Reading data from: {raw_data_path}")
        
        # Create dynamic frame for incremental processing
        datasource = glueContext.create_dynamic_frame.from_options(
            format_options={"multiline": False},
            connection_type="s3",
            format="json",
            connection_options={
                "paths": [raw_data_path],
                "recurse": True
            },
            transformation_ctx="datasource"
        )
        
        # Convert to DataFrame for processing
        df = datasource.toDF()
        
        if df.count() == 0:
            logger.info("No new data to process")
            job.commit()
            return
        
        # Data type conversions
        df = df.withColumn("transaction_date", 
                          to_timestamp(col("transaction_date"), "yyyy-MM-dd HH:mm:ss"))
        df = df.withColumn("amount", col("amount").cast("double"))
        df = df.withColumn("customer_id", col("customer_id").cast("string"))
        df = df.withColumn("transaction_id", col("transaction_id").cast("string"))
        
        # Apply data quality checks
        df_cleaned = validate_data_quality(df)
        
        # Add derived columns
        df_enhanced = add_derived_columns(df_cleaned)
        
        # Write to silver layer with partitioning
        output_path = f"s3://{args['processed-data-bucket']}/silver/transactions/"
        logger.info(f"Writing processed data to: {output_path}")
        
        df_enhanced.write \
            .mode("append") \
            .partitionBy("year", "month", "day") \
            .format("parquet") \
            .option("compression", "snappy") \
            .save(output_path)
        
        logger.info("Bronze to Silver transformation completed successfully")
        
    except Exception as e:
        logger.error(f"Job failed with error: {str(e)}")
        raise e
    
    finally:
        job.commit()

if __name__ == "__main__":
    main() # Data code running
# This is the main entry point for the Glue job
# It initializes the job, reads raw data, processes it, and writes to the silver layer
# The code includes data quality checks and derived column additions
# It uses Spark and Glue contexts for distributed processing
# The job is designed to handle incremental data processing with bookmarking
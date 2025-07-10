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

def create_daily_aggregations(df: DataFrame) -> DataFrame:
    """Create daily transaction aggregations"""
    logger.info("Creating daily aggregations")
    
    daily_agg = df.groupBy("year", "month", "day", "customer_id") \
        .agg(
            count("transaction_id").alias("transaction_count"),
            sum("amount").alias("total_amount"),
            avg("amount").alias("avg_amount"),
            min("amount").alias("min_amount"),
            max("amount").alias("max_amount"),
            countDistinct("transaction_id").alias("unique_transactions")
        ) \
        .withColumn("aggregation_level", lit("daily")) \
        .withColumn("created_at", current_timestamp())
    
    return daily_agg

def create_monthly_aggregations(df: DataFrame) -> DataFrame:
    """Create monthly transaction aggregations"""
    logger.info("Creating monthly aggregations")
    
    monthly_agg = df.groupBy("year", "month", "customer_id") \
        .agg(
            count("transaction_id").alias("transaction_count"),
            sum("amount").alias("total_amount"),
            avg("amount").alias("avg_amount"),
            min("amount").alias("min_amount"),
            max("amount").alias("max_amount"),
            countDistinct("transaction_id").alias("unique_transactions")
        ) \
        .withColumn("aggregation_level", lit("monthly")) \
        .withColumn("created_at", current_timestamp())
    
    return monthly_agg

def create_customer_insights(df: DataFrame) -> DataFrame:
    """Create customer behavior insights"""
    logger.info("Creating customer insights")
    
    # Customer lifetime metrics
    customer_insights = df.groupBy("customer_id") \
        .agg(
            count("transaction_id").alias("lifetime_transactions"),
            sum("amount").alias("lifetime_value"),
            avg("amount").alias("avg_transaction_amount"),
            min("transaction_date").alias("first_transaction_date"),
            max("transaction_date").alias("last_transaction_date"),
            countDistinct("year", "month", "day").alias("active_days")
        )
    
    # Calculate customer tenure in days
    customer_insights = customer_insights.withColumn(
        "customer_tenure_days",
        datediff(col("last_transaction_date"), col("first_transaction_date"))
    )
    
    # Customer segmentation
    customer_insights = customer_insights.withColumn(
        "customer_segment",
        when(col("lifetime_value") > 10000, "high_value")
        .when(col("lifetime_value") > 5000, "medium_value")
        .otherwise("low_value")
    )
    
    customer_insights = customer_insights.withColumn("created_at", current_timestamp())
    
    return customer_insights

def main():
    # Get job parameters
    args = getResolvedOptions(sys.argv, [
        'JOB_NAME',
        'processed-data-bucket'
    ])
    
    # Initialize Spark and Glue contexts
    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    
    logger.info(f"Starting job: {args['JOB_NAME']}")
    logger.info(f"Processed data bucket: {args['processed-data-bucket']}")
    
    try:
        # Read silver data from S3
        silver_data_path = f"s3://{args['processed-data-bucket']}/silver/transactions/"
        logger.info(f"Reading data from: {silver_data_path}")
        
        # Read parquet files
        df = spark.read \
            .format("parquet") \
            .load(silver_data_path)
        
        if df.count() == 0:
            logger.info("No data to process")
            job.commit()
            return
        
        # Create aggregations
        daily_agg = create_daily_aggregations(df)
        monthly_agg = create_monthly_aggregations(df)
        customer_insights = create_customer_insights(df)
        
        # Write daily aggregations
        daily_output_path = f"s3://{args['processed-data-bucket']}/gold/daily_aggregations/"
        logger.info(f"Writing daily aggregations to: {daily_output_path}")
        
        daily_agg.write \
            .mode("overwrite") \
            .partitionBy("year", "month") \
            .format("parquet") \
            .option("compression", "snappy") \
            .save(daily_output_path)
        
        # Write monthly aggregations
        monthly_output_path = f"s3://{args['processed-data-bucket']}/gold/monthly_aggregations/"
        logger.info(f"Writing monthly aggregations to: {monthly_output_path}")
        
        monthly_agg.write \
            .mode("overwrite") \
            .partitionBy("year") \
            .format("parquet") \
            .option("compression", "snappy") \
            .save(monthly_output_path)
        
        # Write customer insights
        customer_output_path = f"s3://{args['processed-data-bucket']}/gold/customer_insights/"
        logger.info(f"Writing customer insights to: {customer_output_path}")
        
        customer_insights.write \
            .mode("overwrite") \
            .format("parquet") \
            .option("compression", "snappy") \
            .save(customer_output_path)
        
        logger.info("Silver to Gold transformation completed successfully")
        
    except Exception as e:
        logger.error(f"Job failed with error: {str(e)}")
        raise e
    
    finally:
        job.commit()

if __name__ == "__main__":
    main()
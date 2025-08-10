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
    
    customer_insights = df.groupBy("customer_id") \
        .agg(
            count("transaction_id").alias("lifetime_transactions"),
            sum("amount").alias("lifetime_value"),
            avg("amount").alias("avg_transaction_amount"),
            min("transaction_date").alias("first_transaction_date"),
            max("transaction_date").alias("last_transaction_date"),
            countDistinct("year", "month", "day").alias("active_days")
        )
    
    customer_insights = customer_insights.withColumn(
        "customer_tenure_days",
        datediff(col("last_transaction_date"), col("first_transaction_date"))
    )
    
    customer_insights = customer_insights.withColumn(
        "customer_segment",
        when(col("lifetime_value") > 10000, "high_value")
        .when(col("lifetime_value") > 5000, "medium_value")
        .otherwise("low_value")
    )
    
    customer_insights = customer_insights.withColumn("created_at", current_timestamp())
    
    return customer_insights

def main():
    #
    # --- FIX 1: ROBUST ARGUMENT PARSING ---
    #
    # Replaced getResolvedOptions with a manual parser to prevent KeyError/IndexError.
    #
    logger.info(f"Starting job. Full command-line arguments: {sys.argv}")
    args = {}
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg.startswith('--'):
            key = arg.lstrip('-')
            if i + 1 < len(sys.argv) and not sys.argv[i+1].startswith('--'):
                args[key] = sys.argv[i+1]
                i += 2
            else:
                args[key] = "true"
                i += 1
        else:
            i += 1
    logger.info(f"Successfully parsed arguments: {args}")
    # --- END OF FIX ---
    
    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    
    logger.info(f"Starting job: {args['JOB_NAME']}")
    logger.info(f"Processed data bucket: {args['processed-data-bucket']}")
    
    try:
        silver_data_path = f"s3://{args['processed-data-bucket']}/silver/transactions/"
        logger.info(f"Reading data from: {silver_data_path}")
        
        # This is the correct way to read a full dataset for aggregation
        df = spark.read.format("parquet").load(silver_data_path)
        
        if df.rdd.isEmpty(): # .rdd.isEmpty() is more efficient than .count() == 0 for some checks
            logger.info("No data in the silver layer to process. Job exiting.")
            return
        
        daily_agg = create_daily_aggregations(df)
        monthly_agg = create_monthly_aggregations(df)
        customer_insights = create_customer_insights(df)
        
        #
        # --- FIX 2: PARTITION KEY VALIDATION ---
        #
        # Filtering nulls before writing to prevent TypeError.
        #
        daily_agg_to_write = daily_agg.filter(col("year").isNotNull() & col("month").isNotNull())
        monthly_agg_to_write = monthly_agg.filter(col("year").isNotNull())
        # --- END OF FIX ---

        daily_output_path = f"s3://{args['processed-data-bucket']}/gold/daily_aggregations/"
        logger.info(f"Writing daily aggregations to: {daily_output_path}")
        daily_agg_to_write.write.mode("overwrite").partitionBy("year", "month").format("parquet").save(daily_output_path)
        
        monthly_output_path = f"s3://{args['processed-data-bucket']}/gold/monthly_aggregations/"
        logger.info(f"Writing monthly aggregations to: {monthly_output_path}")
        monthly_agg_to_write.write.mode("overwrite").partitionBy("year").format("parquet").save(monthly_output_path)
        
        customer_output_path = f"s3://{args['processed-data-bucket']}/gold/customer_insights/"
        logger.info(f"Writing customer insights to: {customer_output_path}")
        customer_insights.write.mode("overwrite").format("parquet").save(customer_output_path)
        
        logger.info("Silver to Gold transformation completed successfully")
        
    except Exception as e:
        logger.error(f"Job failed with error: {str(e)}")
        raise e
    
    finally:
        #
        # --- FIX 3: REMOVED UNNECESSARY BOOKMARKING ---
        #
        # This is an overwrite/aggregation job, so job.commit() is not needed.
        #
        logger.info("Job finished.")
        # job.commit() <-- This line has been removed.
        #
        # --- END OF FIX ---


if __name__ == "__main__":
    main()
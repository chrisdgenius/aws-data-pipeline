# bronze_to_silver.py

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

#
# --- FIX for NameError ---
#
# This block sets up the logger at the global level.
# It MUST be at the top of the file after the imports.
#
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
#
# --- END OF FIX ---
#

def validate_data_quality(df: DataFrame) -> DataFrame:
    """Validate data quality and filter out invalid records"""
    logger.info("Starting data quality validation")
    
    initial_count = df.count()
    logger.info(f"Initial record count: {initial_count}")
    
    df_cleaned = df.dropDuplicates(["transaction_id"])
    
    df_cleaned = df_cleaned.filter(
        col("transaction_id").isNotNull() & 
        col("customer_id").isNotNull() & 
        col("amount").isNotNull() &
        col("transaction_date").isNotNull()
    )
    
    df_cleaned = df_cleaned.filter(col("amount") > 0)
    
    df_cleaned = df_cleaned.withColumn("data_quality_score", lit(1.0))
    df_cleaned = df_cleaned.withColumn("processed_timestamp", current_timestamp())
    
    final_count = df_cleaned.count()
    logger.info(f"Final record count after cleaning: {final_count}")
    logger.info(f"Records removed: {initial_count - final_count}")
    
    return df_cleaned

def add_derived_columns(df: DataFrame) -> DataFrame:
    """Add derived columns for analytics"""
    logger.info("Adding derived columns")
    
    df = df.withColumn("year", year(col("transaction_date")))
    df = df.withColumn("month", month(col("transaction_date")))
    df = df.withColumn("day", dayofmonth(col("transaction_date")))
    df = df.withColumn("hour", hour(col("transaction_date")))
    
    df = df.withColumn("amount_category", 
                      when(col("amount") < 100, "small")
                      .when(col("amount") < 1000, "medium")
                      .otherwise("large"))
    
    df = df.withColumn("transaction_type_derived",
                      when(col("amount") == col("amount").cast("long"), "whole_number")
                      .otherwise("decimal"))
    
    return df

def main():
    # Robust argument parser to handle both key-value and standalone flags
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

    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    
    logger.info(f"Successfully started job: {args['JOB_NAME']}")
    logger.info(f"Raw data bucket: {args['raw-data-bucket']}")
    logger.info(f"Processed data bucket: {args['processed-data-bucket']}")
    
    try:
        raw_data_path = f"s3://{args['raw-data-bucket']}/raw/transactions/"
        logger.info(f"Reading data from: {raw_data_path}")
        
        datasource = glueContext.create_dynamic_frame.from_options(
            format_options={"multiline": False},
            connection_type="s3",
            format="json",
            connection_options={"paths": [raw_data_path], "recurse": True},
            transformation_ctx="datasource"
        )
        
        df = datasource.toDF()
        
        if df.count() == 0:
            logger.info("No new data to process. Job committing and exiting.")
            job.commit()
            return
        
        df = df.withColumn("transaction_date", to_timestamp(col("transaction_date"), "yyyy-MM-dd HH:mm:ss"))
        df = df.withColumn("amount", col("amount").cast("double"))
        df = df.withColumn("customer_id", col("customer_id").cast("string"))
        df = df.withColumn("transaction_id", col("transaction_id").cast("string"))
        
        df_cleaned = validate_data_quality(df)
        df_enhanced = add_derived_columns(df_cleaned)
        
        final_df_to_write = df_enhanced.filter(
            col("year").isNotNull() & col("month").isNotNull() & col("day").isNotNull()
        )

        output_path = f"s3://{args['processed-data-bucket']}/silver/transactions/"
        logger.info(f"Writing processed data to: {output_path}")
        
        final_df_to_write.write \
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
    main()
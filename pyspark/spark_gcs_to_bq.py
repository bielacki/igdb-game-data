#!/usr/bin/python

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json
from pyspark.sql.types import StructType, StructField, StringType, LongType
from google.cloud import storage

# Define GCP project ID and GCS bucket name
project_id = "course-data-engineering"
bucket_name = "igdb-game-data"
pipeline_name = "igdb_source"
destination_dataset_bq = "igdb_source"

# define tables that should be processed
tables = ["games", "popularity_primitives", "popularity_types", "external_game_sources", "game_statuses", "game_types", "genres", "platforms"]

spark = SparkSession.builder.appName("igdb-parquet-processing").getOrCreate()

print("\nSpark session started. Version:", spark.version)


def get_latest_file(project_id, bucket_name, pipeline_name, tables):
    """
    Function to get the latest file for a given table from GCS.
    """
    # Initialize the GCS client
    client = storage.Client(project=project_id)

    # Get the bucket
    bucket = client.get_bucket(bucket_name)

    # Dictionary to store the latest loaded file for each table
    latest_loads = {}

    # Iterate over each table name
    for table in tables:
        # List all blobs in the bucket with the table name as a prefix
        blobs = bucket.list_blobs(prefix=f"{pipeline_name}/{table}/")

        # Find the latest file for the current table
        latest_blob = max(blobs, key=lambda x: x.updated, default=None)

        if latest_blob:
            latest_loads[table] = latest_blob.name
        else:
            latest_loads[table] = None

    return latest_loads


def prepare_df_to_write(latest_files):
    dataframes_to_write = {}
    for table_name, file_name in latest_files.items():
        if file_name is not None:
            if table_name == "games":
                cover_schema = StructType(
                    [
                        StructField("id", LongType(), True),
                        StructField("image_id", StringType(), True),
                        StructField("url", StringType(), True),
                    ]
                )

                df = spark.read.parquet(f"gs://{bucket_name}/{file_name}")

                # Parse the 'cover' JSON string to a struct
                df_transformed = df.withColumn(
                    "cover", from_json(col("cover"), cover_schema)
                )

                dataframes_to_write[table_name] = df_transformed
            else:
                df = spark.read.parquet(f"gs://{bucket_name}/{file_name}")
                dataframes_to_write[table_name] = df
        else:
            print(f"No files found for {table_name} in the bucket.")
    return dataframes_to_write


def write_to_bigquery(table_name, df_final):
    try:
        df_final.write.format("bigquery")\
        .option("writeMethod", "direct")\
        .mode("overwrite")\
        .option("allowFieldAddition", "true")\
        .save(f"{project_id}.{destination_dataset_bq}.{table_name}")
        return f"Data saved to BigQuery table: {project_id}.{destination_dataset_bq}.{table_name}"
    except Exception as e:
        print(e)
        return f"Failed to save data to BigQuery table: {project_id}.{destination_dataset_bq}.{table_name}"


latest_files = get_latest_file(project_id, bucket_name, pipeline_name, tables)

print("Latest files found:\n")
for key, value in latest_files.items():
    print(f"{key}: {value}")

dataframes_to_write = prepare_df_to_write(latest_files)

for table_name, df in dataframes_to_write.items():
    write_to_bigquery(table_name, df)

from pyspark.sql.functions import col, to_date, current_timestamp, lit, trim
from pyspark.sql.types import *

# --- 1. CONFIGURATION ---
storage_account = "stnetflixdatalake001"

bronze_path = f"abfss://bronze@{storage_account}.dfs.core.windows.net/netflix/titles/*/*/*/netflix_titles.csv"
silver_path = f"abfss://silver@{storage_account}.dfs.core.windows.net/netflix_cleaned"
# --- 2. AUTHENTICATION (The Secure Way) ---
# This pulls the CURRENT key directly from Azure Key Vault
storage_key = dbutils.secrets.get(scope="netflix-scope", key="storage-account-key")

spark.conf.set(
    f"fs.azure.account.key.{storage_account}.dfs.core.windows.net", 
    storage_key
)
# --- 3. DEFINE SCHEMA ---
schema = StructType([
    StructField("show_id", StringType(), True),
    StructField("type", StringType(), True),
    StructField("title", StringType(), True),
    StructField("director", StringType(), True),
    StructField("cast", StringType(), True),
    StructField("country", StringType(), True),
    StructField("date_added", StringType(), True),
    StructField("release_year", IntegerType(), True),
    StructField("rating", StringType(), True),
    StructField("duration", StringType(), True),
    StructField("listed_in", StringType(), True),
    StructField("description", StringType(), True)
])

# --- 4. READ DATA (Standard Batch) ---
# We use spark.read instead of readStream to bypass UC metadata checks
df_raw = spark.read.csv(bronze_path, header=True, schema=schema)

print("--- Step 4: Bronze Data Evolution (Initial Load) ---")
df_raw.select("show_id", "title", "date_added").show(5)

# --- 5. TRANSFORMATIONS ---
df_silver = (df_raw
    .withColumn("date_added_clean", to_date(trim(col("date_added")), "MMMM d, yyyy"))
    .fillna({"director": "Unknown", "cast": "Unknown", "country": "Unknown"})
    .withColumn("ingestion_timestamp", current_timestamp())
    .withColumn("source_file", lit("netflix_titles.csv"))
    .filter((col("release_year") >= 1900) & (col("release_year") <= 2026))
)

# --- 6. WRITE TO SILVER ---
# Writing to a direct path (abfss://) is the safe way on Standard Tier
(df_silver.write
    .format("delta")
    .mode("overwrite") 
    .save(silver_path))

print("✅ Silver Layer Processed Successfully!")
display(spark.read.load(silver_path).limit(5))
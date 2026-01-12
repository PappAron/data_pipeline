# MAGIC %pip install "great_expectations<1.0"

dbutils.library.restartPython()

# Databricks notebook source
# Ensure the import path is exact for the legacy version
from great_expectations.dataset.sparkdf_dataset import SparkDFDataset

# --- 1. CONFIGURATION & AUTH ---
storage_account = "stnetflixdatalake001"
scope_name = "netflix-scope"

spark.conf.set(
    f"fs.azure.account.key.{storage_account}.dfs.core.windows.net",
    dbutils.secrets.get(scope=scope_name, key="storage-account-key")
)

gold_path = f"abfss://gold@{storage_account}.dfs.core.windows.net/genre_performance"

# --- 2. LOAD DATA ---
df_spark = spark.read.format("delta").load(gold_path)

# --- 3. CONVERT TO GX DATASET ---
# This converts the Spark DataFrame into a format GX can run tests on
df_gx = SparkDFDataset(df_spark)

# --- 4. RUN EXPECTATIONS ---
# We store the results to check success
results = []
results.append(df_gx.expect_column_values_to_not_be_null("avg_imdb_rating"))
results.append(df_gx.expect_column_values_to_be_between("avg_imdb_rating", min_value=0, max_value=10))
results.append(df_gx.expect_column_min_to_be_between("total_titles", min_value=1))

# --- 5. VALIDATION GATE ---
# Check if any test failed
if not all(r.success for r in results):
    # Print the failing parts for the logs
    for r in results:
        if not r.success:
            print(f"❌ Failed: {r.expectation_config.expectation_type}")
    raise Exception("❌ Data Quality Gate Failed: Gold table metrics are out of bounds!")

print("✅ Data Quality Check Passed: All expectations met.")
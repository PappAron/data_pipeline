# Databricks notebook source
from pyspark.sql.functions import col, avg, count, desc, round

# --- 1. CONFIGURATION ---
storage_account = "stnetflixdatalake001"
scope_name = "netflix-scope"

# AUTHENTICATION (Missing this caused your error)
spark.conf.set(
    f"fs.azure.account.key.{storage_account}.dfs.core.windows.net",
    dbutils.secrets.get(scope=scope_name, key="storage-account-key")
)

# Paths
enriched_path = f"abfss://silver@{storage_account}.dfs.core.windows.net/netflix_omdb_enriched"
gold_path_genre = f"abfss://gold@{storage_account}.dfs.core.windows.net/genre_performance"
gold_path_trends = f"abfss://gold@{storage_account}.dfs.core.windows.net/yearly_trends"

# --- 2. LOAD & PREPARE ---
# Load the enriched silver data
df_silver = spark.read.format("delta").load(enriched_path)

# Data Cleaning for Gold (Type Casting)
df_gold_base = df_silver.withColumn("imdb_rating_float", col("imdb_rating").cast("float"))

# --- 3. TRANSFORM: GENRE PERFORMANCE ---
df_genre_performance = df_gold_base.groupBy("listed_in") \
    .agg(
        count("show_id").alias("total_titles"),
        round(avg("imdb_rating_float"), 2).alias("avg_imdb_rating")
    ) \
    .filter(col("total_titles") > 5) \
    .orderBy(desc("avg_imdb_rating"))

# --- 4. TRANSFORM: CONTENT TRENDS ---
df_yearly_trends = df_gold_base.groupBy("release_year") \
    .agg(
        count("show_id").alias("titles_released"),
        round(avg("imdb_rating_float"), 2).alias("yearly_avg_rating")
    ) \
    .orderBy("release_year")

# --- 5. WRITE TO GOLD LAYER (FILES) ---
# Direct file writes work on all Tiers
df_genre_performance.write.format("delta").mode("overwrite").save(gold_path_genre)
df_yearly_trends.write.format("delta").mode("overwrite").save(gold_path_trends)

# --- 6. REGISTER TABLES (STANDARD TIER COMPATIBLE) ---
# We avoid .saveAsTable() to prevent Unity Catalog errors. 
# Instead, we register the paths to the Hive Metastore.
spark.sql("CREATE DATABASE IF NOT EXISTS hive_metastore.netflix_analytics")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS hive_metastore.netflix_analytics.genre_performance 
    USING DELTA LOCATION '{gold_path_genre}'
""")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS hive_metastore.netflix_analytics.yearly_trends 
    USING DELTA LOCATION '{gold_path_trends}'
""")

print("✅ Gold layer aggregates created and registered successfully!")
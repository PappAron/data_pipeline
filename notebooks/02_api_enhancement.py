# Databricks notebook source
import requests
from pyspark.sql.functions import udf, col
from pyspark.sql.types import MapType, StringType
from delta.tables import DeltaTable

# --- 1. CONFIG & SECRETS ---
storage_account = "stnetflixdatalake001"
scope_name = "netflix-scope"

# Get Secrets
api_key = dbutils.secrets.get(scope=scope_name, key="omdb-api-key")

# Authenticate to Storage
spark.conf.set(f"fs.azure.account.key.{storage_account}.dfs.core.windows.net", 
               dbutils.secrets.get(scope=scope_name, key="storage-account-key"))

# Paths
silver_path = f"abfss://silver@{storage_account}.dfs.core.windows.net/netflix_cleaned"
enriched_path = f"abfss://silver@{storage_account}.dfs.core.windows.net/netflix_omdb_enriched"

# --- 2. API FUNCTION & UDF ---
def fetch_omdb_data(title):
    base_url = "http://www.omdbapi.com/"
    try:
        # Note: In a production app, you'd use a session object for connection pooling
        response = requests.get(base_url, params={"t": title, "apikey": api_key}, timeout=5)
        if response.status_code == 200:
            data = response.json()
            if data.get("Response") == "True":
                return {
                    "imdb_rating": data.get("imdbRating"),
                    "awards": data.get("Awards"),
                    "box_office": data.get("BoxOffice")
                }
        return {"imdb_rating": "N/A", "awards": "N/A", "box_office": "N/A"}
    except:
        return {"imdb_rating": None, "awards": None, "box_office": None}

omdb_udf = udf(fetch_omdb_data, MapType(StringType(), StringType()))

# --- 3. INCREMENTAL LOGIC (Anti-Join) ---
df_silver = spark.read.format("delta").load(silver_path)

try:
    df_existing = spark.read.format("delta").load(enriched_path)
    # Anti-join finds records in Silver that ARE NOT in Enriched yet
    df_to_enrich = df_silver.join(df_existing, "show_id", "left_anti").limit(50) # Limit for testing
except:
    print("Enriched table not found. Performing initial load...")
    df_to_enrich = df_silver.limit(50)

if df_to_enrich.count() == 0:
    dbutils.notebook.exit("Success: No new titles to enrich.")

# --- 4. ENRICH & FLATTEN ---
df_enriched = df_to_enrich.withColumn("omdb", omdb_udf(col("title"))) \
                          .withColumn("imdb_rating", col("omdb.imdb_rating")) \
                          .withColumn("awards", col("omdb.awards")) \
                          .withColumn("box_office", col("omdb.box_office")) \
                          .drop("omdb")

# --- 5. DELTA MERGE (UPSERT) ---
# Direct path-based merge to bypass Unity Catalog
if DeltaTable.isDeltaTable(spark, enriched_path):
    target_table = DeltaTable.forPath(spark, enriched_path)
    target_table.alias("target").merge(
        df_enriched.alias("updates"),
        "target.show_id = updates.show_id"
    ).whenMatchedUpdateAll().whenNotMatchedInsertAll().execute()
else:
    df_enriched.write.format("delta").mode("overwrite").save(enriched_path)

print(f"✅ Incremental API enrichment complete. Data saved to: {enriched_path}")
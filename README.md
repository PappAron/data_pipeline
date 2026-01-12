# MSc Data Engineering: Netflix Cloud Pipeline Documentation
## 1. Analytical Goal

The goal of this project is to create a curated dataset that allows analysis of:

- Top Netflix titles by IMDb rating and box office revenue  
- Average ratings by genre or country  
- Trend of content additions over time  
- Correlation between content type (Movie/TV Show) and ratings  
- Count of award-winning content per year  

The pipeline transforms raw data into **analytics-ready tables** suitable for dashboards or further analysis.

---

## 2. Cloud Resources Overview
The project environment is a fully automated **Lakehouse** implementation deployed on **Microsoft Azure** using **Terraform (IaC)**. The architecture follows a hub-and-spoke security model to protect sensitive data while maintaining high-performance compute.

### Resource Specification
| Component | Azure Service | Specification / Role |
| :--- | :--- | :--- |
| **Storage** | **ADLS Gen2** | **Account:** `stnetflixdatalake001`. Utilizes a Hierarchical Namespace for atomic directory operations and high-performance Spark metadata management. |
| **Compute** | **Azure Databricks** | **Cluster:** `Standard_D4s_v3` (Single Node). Configured with static Spark flags to enforce compatibility with the Standard Tier and bypass Unity Catalog dependencies. |
| **Orchestration** | **Databricks Jobs** | Orchestrates 4 decoupled notebooks into a **DAG (Directed Acyclic Graph)**, managing dependencies from raw ingestion to final validation. |
| **Secrets** | **Azure Key Vault** | `kv-netflix-secrets-001`. Acts as the central vault for Storage Keys and OMDb API credentials; accessed via Databricks Secret Scopes. |
| **Catalog** | **Hive Metastore** | Serves as the metadata registry. Tables are registered as "External Tables" to ensure storage decoupling from the compute workspace. |



---

## 3. Security & Storage Layout

### Security Implementation
* **Zero-Trust Access:** Authentication is managed via **Service Principal** OIDs. No plaintext keys are stored in the notebooks.
* **Secret Scopes:** Azure Key Vault is linked to Databricks, allowing the `dbutils.secrets` API to retrieve credentials over the Azure backbone network.
* **Redaction:** Databricks automatically redacts secrets from notebook outputs and logs, preventing accidental credential exposure.

### Storage Layout (Medallion Pattern)

* **Bronze:** Persistent landing zone for raw CSV files. Stores Autoloader checkpoints to manage incremental state.
* **Silver:** Cleaned and enriched data. Includes transformations and OMDb API integration (IMDb ratings, awards).
* **Gold:** Highly aggregated, business-ready tables (Genre Performance, Yearly Trends) optimized for BI tools.

### Cost Management
* **Single Node Optimization:** Used `local[*]` master to eliminate worker-to-worker data transfer costs.
* **Auto-Termination:** Cluster set to terminate after 20 minutes of inactivity to minimize DBU consumption.
* **Tier Strategy:** Used the **Standard Tier** to reduce cost to handle metadata through the Hive Metastore instead of the more expensive Unity Catalog.
---

## 4. Engineering Justification & Design Trade-offs

### Table Tech: Delta Lake
We standardized on **Delta Lake** over Parquet or Iceberg. Delta provides **ACID compliance**, which is critical for our Silver-layer API enrichment. If the API call fails mid-batch, Delta ensures the table remains in a consistent state without partial, corrupted writes.

### Orchestration: Incremental vs. Batch
We implemented **Incremental Orchestration** using **Databricks Autoloader**. 
* **Justification:** Unlike a simple one-time batch move, Autoloader tracks file arrival state via checkpoints. This allows the pipeline to process only "new" data in subsequent runs, significantly reducing compute costs.

### Idempotency & Error Handling
* **Idempotency:** The enrichment layer uses the **Delta MERGE (Upsert)** operation. This ensures that re-running the pipeline results in updates to existing records rather than duplicates, making the process safe to restart at any time.
* **Error Handling:** API calls are wrapped in `try-except` blocks to handle network timeouts gracefully. Static cluster configurations are enforced via Terraform to prevent session-level failures.

### Lineage & Observability
* **Observability:** We implemented a **Data Quality Gate** using **Great Expectations (v0.18.x)**.
* **Lineage:** Every record includes audit columns: `source_file` and `ingestion_timestamp`.
* **Fail-Fast Mechanism:** If the Gold layer fails validation (e.g., negative title counts or null ratings), the pipeline triggers an exception, preventing the "poisoning" of downstream BI reports.


---

## 5. Infrastructure as Code (IaC)

### Repository Structure
```text
data_pipeline/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── notebooks.tf
├── scripts/
│   ├── upload_to_blob.py
│   └── run_pipeline.ps1
└── notebooks/
    ├── 01_bronze_to_silver
    ├── 02_api_enhancement
    ├── 03_silver_to_gold
    └── 04_data_quality
```


## 6. Schema Documentation

### Netflix CSV (Raw)

| Column | Type | Description | Example |
|--------|------|------------|---------|
| show_id | string | Unique ID | `s1` |
| type | string | Movie or TV Show | `Movie` |
| title | string | Title | `Guardians of the Galaxy Vol. 2` |
| director | string | Director | `James Gunn` |
| cast | string | Actors | `Chris Pratt, Zoe Saldaña` |
| country | string | Country of production | `United States` |
| date_added | date | Date added on Netflix | `25-Sep-2021` |
| release_year | int | Year of release | `2017` |
| rating | string | TV rating | `PG-13` |
| duration | string | Minutes (Movies) or Seasons (TV Shows) | `136 min` |
| listed_in | string | Genre(s) | `Action, Adventure, Comedy` |
| description | string | Summary | `"The Guardians struggle ..."` |

**Volume:** ~8,800 rows (~10 MB)  
**Update Cadence:** Static CSV for project use  

### OMDb API (Raw)

| Field | Type | Description | Example |
|-------|------|------------|---------|
| Title | string | Movie/TV show title | `Guardians of the Galaxy Vol. 2` |
| Year | int | Release year | `2017` |
| Rated | string | MPAA/TV rating | `PG-13` |
| Released | date | Release date | `05 May 2017` |
| Runtime | string | Duration | `136 min` |
| Genre | string | Genre(s) | `Action, Adventure, Comedy` |
| Director | string | Director | `James Gunn` |
| Writer | string | Writers | `James Gunn, Dan Abnett, Andy Lanning` |
| Actors | string | Cast | `Chris Pratt, Zoe Saldaña, Dave Bautista` |
| Plot | string | Summary | `"The Guardians struggle ..."` |
| Language | string | Language | `English` |
| Country | string | Production country | `United States` |
| Awards | string | Awards won | `Nominated for 1 Oscar. 15 wins & 60 nominations total` |
| Poster | string | Poster URL | `https://m.media-amazon.com/...` |
| Ratings | array of dict | Ratings from multiple sources | `[{"Source":"Internet Movie Database","Value":"7.6/10"}]` |
| imdbRating | float | IMDb rating | `7.6` |
| BoxOffice | string | Box office revenue | `$389,813,101` |

**Volume:** ~8,800 rows (~1–2 MB cached JSON)  
**Update Cadence:** Real-time API; static snapshot used for project  

---


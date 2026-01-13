terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.0"
    }
  }
}

provider "databricks" {
  host = var.databricks_url
}

resource "databricks_cluster" "netflix_cluster" {
  cluster_name            = "Netflix-Project-Cluster"
  spark_version           = "13.3.x-scala2.12"
  node_type_id            = "Standard_D4s_v3"
  num_workers             = 0
  autotermination_minutes = 20
  data_security_mode      = "NONE"

  spark_conf = {
    "spark.master" = "local[*]"
    "spark.databricks.unityCatalog.enabled" = "false"
    "spark.databricks.cloudFiles.useNotifications" = "false"
  }

  library {
    pypi {
      package = "great_expectations"
    }
  }
}

resource "databricks_secret_scope" "kv" {
  name = "netflix-scope"
  initial_manage_principal = "users"

  keyvault_metadata {
    resource_id = var.key_vault_id
    dns_name    = var.key_vault_uri
  }
}

# --- NOTEBOOK UPLOADS ---
resource "databricks_notebook" "bronze_to_silver" {
  path     = "/Shared/netflix/01_bronze_to_silver"
  language = "PYTHON"
  source   = "../../notebooks/01_bronze_to_silver.py"
}

resource "databricks_notebook" "api_enhancement" {
  path     = "/Shared/netflix/02_api_enhancement"
  language = "PYTHON"
  source   = "../../notebooks/02_api_enhancement.py"
}

resource "databricks_notebook" "silver_to_gold" {
  path     = "/Shared/netflix/03_silver_to_gold"
  language = "PYTHON"
  source   = "../../notebooks/03_silver_to_gold.py"
}

resource "databricks_notebook" "data_quality" {
  path     = "/Shared/netflix/04_data_quality"
  language = "PYTHON"
  source   = "../../notebooks/04_data_quality.py"
}

resource "databricks_job" "netflix_pipeline" {
  name = "Netflix_Weekly_Data_Pipeline"

  schedule {
    quartz_cron_expression = "0 0 0 ? * MON"
    timezone_id            = "UTC"
    pause_status           = "UNPAUSED" 
  }

  task {
    task_key = "Bronze_to_Silver"
    notebook_task { notebook_path = databricks_notebook.bronze_to_silver.path }
    existing_cluster_id = databricks_cluster.netflix_cluster.id
  }

  task {
    task_key = "API_Enhancement"
    depends_on {
      task_key = "Bronze_to_Silver"
    }
    
    existing_cluster_id = databricks_cluster.netflix_cluster.id

    notebook_task {
      notebook_path = databricks_notebook.api_enhancement.path
    }

    health {
      rules {
        metric = "RUN_DURATION_SECONDS"
        op     = "GREATER_THAN"
        value  = 3600 # 1 hour timeout example
      }
    }
  }

  task {
    task_key = "Silver_to_Gold"
    depends_on { task_key = "API_Enhancement" }
    notebook_task { notebook_path = databricks_notebook.silver_to_gold.path }
    existing_cluster_id = databricks_cluster.netflix_cluster.id
  }

  task {
    task_key = "Data_Quality_Check"
    depends_on { task_key = "Silver_to_Gold" }
    notebook_task { notebook_path = databricks_notebook.data_quality.path }
    existing_cluster_id = databricks_cluster.netflix_cluster.id
  }

  email_notifications {
    on_failure = [var.email_notification]
  }
}

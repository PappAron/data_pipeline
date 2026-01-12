terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.0"
    }
  }
}

# --- 1. PROVIDERS ---
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}

# Get Current Azure Client Config (used for Key Vault Access Policy)
data "azurerm_client_config" "current" {}

# --- 2. AZURE CORE INFRASTRUCTURE ---
resource "azurerm_resource_group" "netflix_rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "datalake" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.netflix_rg.name
  location                 = azurerm_resource_group.netflix_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true 
}

resource "azurerm_storage_container" "layers" {
  for_each              = toset(["bronze", "silver", "gold"])
  name                  = each.key
  storage_account_name  = azurerm_storage_account.datalake.name
  container_access_type = "private"
}

resource "azurerm_databricks_workspace" "example" {
  name                = var.workspace_name
  resource_group_name = azurerm_resource_group.netflix_rg.name
  location            = azurerm_resource_group.netflix_rg.location
  sku                 = "standard"
}

resource "azurerm_key_vault" "vault" {
  name                        = var.key_vault_name
  location                    = azurerm_resource_group.netflix_rg.location
  resource_group_name         = azurerm_resource_group.netflix_rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enable_rbac_authorization   = false

  # ADD THIS BLOCK
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }
}


# --- 3. DATABRICKS CONFIGURATION ---
provider "databricks" {
  host = azurerm_databricks_workspace.example.workspace_url
}

resource "databricks_cluster" "netflix_cluster" {
  cluster_name            = "Netflix-Project-Cluster"
  spark_version           = "13.3.x-scala2.12"
  node_type_id            = "Standard_D4s_v3"
  autotermination_minutes = 20
  num_workers             = 0

  # --- CRITICAL CHANGES FOR STANDARD TIER ---
  # "NONE" maps to "No isolation shared" in the UI
  data_security_mode = "NONE" 

  spark_conf = {
    "spark.master" : "local[*]"

    # Force disable Unity Catalog features that trigger AnalysisExceptions
    "spark.databricks.unityCatalog.enabled" : "false"
    "spark.databricks.delta.preview.enabled" : "true"
    "spark.databricks.cloudFiles.useNotifications" : "false"
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
    resource_id = azurerm_key_vault.vault.id
    dns_name    = azurerm_key_vault.vault.vault_uri
  }
}

# --- 4. NOTEBOOK UPLOADS ---
resource "databricks_notebook" "bronze_to_silver" {
  path     = "/Shared/netflix/01_bronze_to_silver"
  language = "PYTHON"
  source   = "../notebooks/01_bronze_to_silver.py"
}

resource "databricks_notebook" "api_enhancement" {
  path     = "/Shared/netflix/02_api_enhancement"
  language = "PYTHON"
  source   = "../notebooks/02_api_enhancement.py"
}

resource "databricks_notebook" "silver_to_gold" {
  path     = "/Shared/netflix/03_silver_to_gold"
  language = "PYTHON"
  source   = "../notebooks/03_silver_to_gold.py"
}

resource "databricks_notebook" "data_quality" {
  path     = "/Shared/netflix/04_data_quality"
  language = "PYTHON"
  source   = "../notebooks/04_data_quality.py"
}

# This resource grants the Databricks Service permission to read Key Vault secrets
resource "azurerm_key_vault_access_policy" "databricks_policy" {
  key_vault_id = azurerm_key_vault.vault.id # Adjust to match your KV resource name
  tenant_id    = data.azurerm_client_config.current.tenant_id
  
  # This is the Global Application ID for Azure Databricks
  object_id    = "dac2bfcb-0aec-4d63-b607-3cf49d93ceb4" 

  secret_permissions = [
    "Get",
    "List"
  ]
}

# --- 5. WORKFLOW ORCHESTRATION ---
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

# --- 6. OUTPUTS ---
output "storage_connection_string" {
  value     = azurerm_storage_account.datalake.primary_connection_string
  sensitive = true
}

output "databricks_job_id" {
  value = databricks_job.netflix_pipeline.id
}

output "databricks_url" {
  value = azurerm_databricks_workspace.example.workspace_url
}
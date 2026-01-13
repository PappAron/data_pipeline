terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}

data "azurerm_client_config" "current" {}

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
  name                      = var.key_vault_name
  location                  = azurerm_resource_group.netflix_rg.location
  resource_group_name       = azurerm_resource_group.netflix_rg.name
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "dac2bfcb-0aec-4d63-b607-3cf49d93ceb4" # Global Databricks ID
    secret_permissions = ["Get", "List"]
  }

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

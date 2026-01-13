variable "subscription_id" {
  description = "The Azure Subscription ID"
  type        = string
  default     = "a1cf846f-8f2a-47da-b67f-997e3ee3bcff"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "UK South"
}

variable "resource_group_name" {
  type    = string
  default = "rg-netflix-de-project"
}

variable "storage_account_name" {
  type    = string
  default = "stnetflixdatalake001"
}

variable "workspace_name" {
  type    = string
  default = "dbw-netflix-analytics"
}

variable "key_vault_name" {
  type    = string
  default = "kv-netflix-secrets-001"
}

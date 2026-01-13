variable "email_notification" {
  description = "Email to notify on pipeline failure"
  type        = string
  default     = "papp.aron03@gmail.com"
}

variable "databricks_url" {
  type        = string
  description = "The URL of the created Databricks workspace"
}

variable "key_vault_id" {
  type        = string
  description = "The Resource ID of the Azure Key Vault"
}

variable "key_vault_uri" {
  type        = string
  description = "The URI of the Azure Key Vault"
}
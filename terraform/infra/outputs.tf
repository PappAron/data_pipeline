output "storage_connection_string" {
  value     = azurerm_storage_account.datalake.primary_connection_string
  sensitive = true
}

output "databricks_url" {
  value = azurerm_databricks_workspace.example.workspace_url
}

output "key_vault_id" {
  value = azurerm_key_vault.vault.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.vault.vault_uri
}
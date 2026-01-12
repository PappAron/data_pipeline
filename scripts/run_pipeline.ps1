terraform "-chdir=../terraform" init
terraform "-chdir=../terraform" plan
terraform "-chdir=../terraform" apply -auto-approve

# Settings
$VAULT_NAME = "kv-netflix-secrets-001" 
$STORAGE_ACC_NAME = "stnetflixdatalake001"

Write-Host "--- Step 2: Syncing Secrets to Key Vault ---" -ForegroundColor Cyan

# 2a. Handle OMDb API Key
$SECRET_OMDB = "omdb-api-key"
$checkOmdb = az keyvault secret list --vault-name $VAULT_NAME --query "[?name=='$SECRET_OMDB'].name" -o tsv

if (-not $checkOmdb) {
    Write-Host "⚠️ OMDb API Key not found in Vault." -ForegroundColor Yellow
    $userKey = Read-Host "Please enter your OMDb API Key"
    az keyvault secret set --vault-name $VAULT_NAME --name $SECRET_OMDB --value $userKey
}

# 2b. Handle Storage Account Key (Automated - no prompt needed)
Write-Host "Syncing Storage Account Key..." -ForegroundColor Gray
$storageKey = az storage account keys list --account-name $STORAGE_ACC_NAME --query "[0].value" -o tsv
az keyvault secret set --vault-name $VAULT_NAME --name "storage-account-key" --value $storageKey

# 3. Extract Values for Environment
Write-Host "Extracting connection strings..." -ForegroundColor Gray
$connString = terraform output -raw storage_connection_string
$omdbKey = az keyvault secret show --name $SECRET_OMDB --vault-name $VAULT_NAME --query value -o tsv

# 4. Inject into Environment Variables
$env:AZURE_STORAGE_CONNECTION_STRING = $connString
$env:OMDB_API_KEY = $omdbKey
$conn = terraform output -raw storage_connection_string
$env:AZURE_STORAGE_CONNECTION_STRING = $conn

# 5. Run Ingestion
Write-Host "--- Step 3: Running Ingestion ---" -ForegroundColor Green
python .\scripts\upload_to_blob.py

Write-Host "--- Automated Cloud Handshake ---" -ForegroundColor Cyan

az keyvault set-policy --name "kv-netflix-secrets-001" --object-id "dac2bfcb-0aec-4d63-b607-3cf49d93ceb4" --secret-permissions get list

# Fetch current Workspace URL and Job ID from Terraform
$WS_URL = (terraform -chdir=terraform output -raw databricks_url).Trim()
$JOB_ID = (terraform -chdir=terraform output -raw databricks_job_id).Trim()

# Generate a temporary Azure AD Token (No UI needed)
Write-Host "Generating temporary AAD Token..." -ForegroundColor Gray
$env:DATABRICKS_TOKEN = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query "accessToken" -o tsv
$env:DATABRICKS_HOST = "https://$WS_URL"

# Trigger the Job
Write-Host "Triggering Job $JOB_ID on $WS_URL" -ForegroundColor Yellow
databricks jobs run-now --job-id $JOB_ID

Write-Host "🚀 Success! The cloud job is now running." -ForegroundColor Green

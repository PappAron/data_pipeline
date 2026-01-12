# Step 1: Infrastructure Sync
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

# 2b. Handle Storage Account Key (Automated)
Write-Host "Syncing Storage Account Key..." -ForegroundColor Gray
$storageKey = az storage account keys list --account-name $STORAGE_ACC_NAME --query "[0].value" -o tsv
az keyvault secret set --vault-name $VAULT_NAME --name "storage-account-key" --value $storageKey

# 3. Extract Values for Environment (FIXED PATHS HERE)
Write-Host "Extracting connection strings..." -ForegroundColor Gray
# We must use -chdir here or it will return an error/blank
$connString = (terraform "-chdir=../terraform" output -raw storage_connection_string).Trim()
$omdbKey = az keyvault secret show --name $SECRET_OMDB --vault-name $VAULT_NAME --query value -o tsv

# 4. Inject into Environment Variables
$env:AZURE_STORAGE_CONNECTION_STRING = $connString
$env:OMDB_API_KEY = $omdbKey

# 5. Run Ingestion
Write-Host "--- Step 3: Running Ingestion ---" -ForegroundColor Green
python upload_to_blob.py

Write-Host "--- Automated Cloud Handshake ---" -ForegroundColor Cyan

# Ensure Databricks can access the Vault
az keyvault set-policy --name $VAULT_NAME --object-id "dac2bfcb-0aec-4d63-b607-3cf49d93ceb4" --secret-permissions get list

# Fetch current Workspace URL and Job ID from Terraform (FIXED PATHS HERE)
$WS_URL = (terraform "-chdir=../terraform" output -raw databricks_url).Trim()
$JOB_ID = (terraform "-chdir=../terraform" output -raw databricks_job_id).Trim()

# Generate a temporary Azure AD Token
Write-Host "Generating temporary AAD Token..." -ForegroundColor Gray
$env:DATABRICKS_TOKEN = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query "accessToken" -o tsv
$env:DATABRICKS_HOST = "https://$WS_URL"

# Trigger the Job
Write-Host "Triggering Job $JOB_ID on $WS_URL" -ForegroundColor Yellow
databricks jobs run-now --job-id $JOB_ID

Write-Host "🚀 Success! The cloud job is now running." -ForegroundColor Green
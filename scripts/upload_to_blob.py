import os
from azure.storage.blob import BlobServiceClient

# Now automatically fetched from the system environment
CONNECTION_STRING = os.getenv("AZURE_STORAGE_CONNECTION_STRING")
CONTAINER_NAME = "bronze"
LOCAL_FILE = "data/netflix_titles.csv"

def upload():
    if not CONNECTION_STRING:
        print("❌ Error: Connection string not found. Ensure the environment variable is set.")
        return

    blob_service_client = BlobServiceClient.from_connection_string(CONNECTION_STRING)
    blob_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob="netflix/netflix_titles.csv")

    with open(LOCAL_FILE, "rb") as data:
        blob_client.upload_blob(data, overwrite=True)
    print("✅ Successfully uploaded Netflix CSV to Bronze!")

if __name__ == "__main__":
    upload()
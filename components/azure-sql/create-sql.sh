#!/bin/bash

set -euo pipefail

echo "retrieving storage connection string"
AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name $AZURE_STORAGE_ACCOUNT -g $RESOURCE_GROUP -o tsv)
AZURE_STORAGE_KEY=$(az storage account keys list -g $RESOURCE_GROUP -n $AZURE_STORAGE_ACCOUNT -o tsv --query "[0].value")

echo "deploying azure sql"
echo ". server: $SQL_SERVER_NAME"
echo ". database: $SQL_DATABASE_NAME"

# Create a logical server in the resource group
az sql server create \
    --name $SQL_SERVER_NAME \
    --resource-group $RESOURCE_GROUP \
    --admin-user serveradmin \
    --admin-password "$SQL_ADMIN_PASS" \
    -o tsv >> log.txt

echo "Enabling access from Azure"
# Configure a firewall rule for the server
az sql server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --server $SQL_SERVER_NAME \
    -n AllowAllWindowsAzureIps \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    -o tsv >> log.txt

echo "deploying SQL database"
az sql db create --resource-group "$RESOURCE_GROUP" \
    --server $SQL_SERVER_NAME \
    --name $SQL_DATABASE_NAME \
    --service-objective $SQL_SKU \
    -o tsv >> log.txt

echo 'creating file share'
az storage share create -n sqlprovision --connection-string $AZURE_STORAGE_CONNECTION_STRING \
    -o tsv >> log.txt

echo 'uploading provisioning scripts'
az storage file upload-batch --source ../components/azure-sql/provision \
    --destination sqlprovision --connection-string $AZURE_STORAGE_CONNECTION_STRING \
    -o tsv >> log.txt

echo 'running provisioning scripts in container instance'
az container create -g $RESOURCE_GROUP -n sqlprovision \
    --image mcr.microsoft.com/mssql-tools:v1 \
    --azure-file-volume-account-name $AZURE_STORAGE_ACCOUNT --azure-file-volume-account-key $AZURE_STORAGE_KEY \
    --azure-file-volume-share-name sqlprovision --azure-file-volume-mount-path /sqlprovision \
    --command-line "bash /sqlprovision/provision.sh" \
    --environment-variables SQL_SERVER_NAME=$SQL_SERVER_NAME SQL_DATABASE_NAME=$SQL_DATABASE_NAME \
    --secure-environment-variables SQL_ADMIN_PASS="$SQL_ADMIN_PASS" \
    --cpu 1 --memory 1 \
    --restart-policy Never \
    -o tsv >> log.txt

echo 'deleting container instance'
az container delete -g $RESOURCE_GROUP -n sqlprovision --yes \
    -o tsv >> log.txt
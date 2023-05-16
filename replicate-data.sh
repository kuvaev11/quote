#!/bin/bash

# Define variables for vault and secret names
from_keyvault_name=ls-usc1-qa-akv-5-gyq
from_secret_username=DB-USERNAME
from_secret_password=DB-PASSWORD

to_keyvault_name=ls-usc1-dev-akv-9-yox
to_secret_username=DB-USERNAME
to_secret_password=DB-PASSWORD

# Define variables for Azure Storage account and container
storage_account_name=your_storage_account_name
storage_container_name=your_storage_container_name

# Usage: replicate_data.sh db_name from_server to_server
#
# This script securely replicates data between two PostgreSQL databases using Azure Key Vault
# to store and retrieve the database connection secrets and Azure Backup Storage for replication.
# It requires the following command-line arguments:
#
# db_name: The name of the database to replicate, separated by commas (no spaces).
# from_server: The IP address or hostname of the server hosting the source database.
# to_server: The IP address or hostname of the server hosting the target database.
#
# Example usage:
# ./replicate_data.sh ls-usc1-qa <source_server_name>.postgres.database.azure.com <target_server_name>.postgres.database.azure.com
#
# ./replicate_data.sh ls-usc1-qa-pgs-p1-cvu ls-usc1-qa-pgs-p1-cvu.postgres.database.azure.com ls-usc1-dev-pgs-p1-hcz.postgres.database.azure.com
#
# Note: This script requires that you have Azure CLI installed and configured on your local machine.

# Check number of command-line arguments
if [[ $# -ne 3 ]]; then
    echo "Error: Incorrect number of arguments."
    echo "Usage: $0 db_name from_server to_server"
    exit 1
fi

# Extract command-line arguments
IFS=',' read -ra db_names <<< "$1"
from_server=$2
to_server=$3

# Retrieve database connection secrets from Azure Key Vault
from_db_password=$(az keyvault secret show --vault-name $from_keyvault_name --name $from_secret_password --query 'value' -o tsv)
to_db_password=$(az keyvault secret show --vault-name $to_keyvault_name --name $to_secret_password --query 'value' -o tsv)

# Iterate over the list of database names
for db_name in "${db_names[@]}"; do
    echo "Replicating database: $db_name"

    # Dump the source database
    pg_dump --dbname=postgresql://$from_secret_username:$from_db_password@localhost:5432/$db_name --file=$db_name.dump

    # Upload the dump file to Azure Backup Storage
    az storage blob upload --account-name $storage_account_name --account-key $storage_account_key --type block --container-name $storage_container_name --name $db_name.dump --type block --file $db_name.dump

    # Download the dump file from Azure Backup Storage to the target server
    az storage blob download --account-name $storage_account_name --account-key $storage_account_key --container-name $storage_container_name --name $db_name.dump --file $db_name.dump

    # Restore the database on the target server
    pg_restore --dbname=postgresql://$to_secret_username:$to_db_password@localhost:5433/$db_name --clean --create $db_name.dump

    # Cleanup dump files on the target server and remove the dump file from Azure Backup Storage
    rm $db_name.dump
    az storage blob delete --account-name $storage_account_name --account-key $storage

#!/bin/bash

# Strict mode, fail on any error
set -euo pipefail

echo 'getting shared access key'
EVENTHUB_CS=$(az eventhubs namespace authorization-rule keys list -g $RESOURCE_GROUP --namespace-name $EVENTHUB_NAMESPACE --name Listen --query "primaryConnectionString" -o tsv)

echo "getting Data Lake Storage Gen2 key"
STORAGE_GEN2_KEY=$(az storage account keys list -n $AZURE_STORAGE_ACCOUNT_GEN2 -g $RESOURCE_GROUP --query '[?keyName==`key1`].value' -o tsv)

echo 'writing Databricks secrets'
databricks secrets put --scope "MAIN" --key "event-hubs-read-connection-string" --string-value "$EVENTHUB_CS;EntityPath=$EVENTHUB_NAME"

checkpoints_dir=dbfs:/streaming_at_scale/checkpoints/streaming-geofencing
echo "Deleting checkpoints directory $checkpoints_dir"
databricks fs rm -r "$checkpoints_dir"

source ../streaming/databricks/job/run-databricks-job.sh eventhubs-to-geofencing false "$(cat <<JQ
  .libraries += [ { "pypi": { "package": "Shapely" } } ]
  | .libraries += [ { "pypi": { "package": "geojson" } } ]
  | .notebook_task.base_parameters."eventhub-consumergroup" = "$EVENTHUB_CG"
  | .notebook_task.base_parameters."eventhub-maxEventsPerTrigger" = "$DATABRICKS_MAXEVENTSPERTRIGGER"
JQ
)"
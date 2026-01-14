#!/bin/bash
set -euo pipefail

# --- Configuration (with defaults) ---
# Arguments passed from setup-gcp.sh
VM_NAME="$1"
ZONE="$2"
FIREWALL_RULE_NAME="$3"
PROJECT_ID="$4"
TAGS="$5"


echo "Adding network tags '$TAGS' to VM '$VM_NAME'..."
gcloud compute instances add-tags "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --tags="$TAGS"

echo "Checking if firewall rule '$FIREWALL_RULE_NAME' already exists..."
if gcloud compute firewall-rules describe "$FIREWALL_RULE_NAME" --project="$PROJECT_ID" &>/dev/null; then
  echo "Firewall rule '$FIREWALL_RULE_NAME' already exists. Exiting."
  exit 0
fi

echo "Firewall rule '$FIREWALL_RULE_NAME' does not exist. Proceeding with creation."
gcloud compute firewall-rules create "$FIREWALL_RULE_NAME" \
    --project="$PROJECT_ID" \
    --description="Allow incoming HTTP and HTTPS traffic" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80,tcp:443 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$TAGS"

echo "Firewall rule '$FIREWALL_RULE_NAME' created successfully."

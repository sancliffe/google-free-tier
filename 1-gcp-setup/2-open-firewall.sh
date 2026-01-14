#!/bin/bash
set -euo pipefail

# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Default values
ZONE="us-west1-a"
VM_NAME="free-tier-vm"
TAGS="http-server,https-server"
FIREWALL_RULE_NAME="allow-http-https"
PROJECT_ID=""

# Source config file if it exists
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=config.sh
    source "${CONFIG_FILE}"
fi

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-name)    VM_NAME="$2"; shift 2;;
        --zone)       ZONE="$2"; shift 2;;
        --tags)       TAGS="$2"; shift 2;;
        --firewall-rule-name) FIREWALL_RULE_NAME="$2"; shift 2;;
        --project-id) PROJECT_ID="$2"; shift 2;;
        *)            echo "Unknown option: $1"; exit 1;;
    esac
done

# If PROJECT_ID is not set by args or config, get it from gcloud
if [[ -z "${PROJECT_ID}" ]]; then
    PROJECT_ID=$(gcloud config get-value project)
fi


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

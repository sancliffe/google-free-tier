#!/bin/bash
set -euo pipefail

# --- Configuration (with defaults) ---
# Arguments passed from setup-gcp.sh
VM_NAME="$1"
ZONE="$2"
FIREWALL_RULE_NAME="$3"
PROJECT_ID="$4"
TAGS="$5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
    log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [✅ SUCCESS] $*"; }
fi

log_info "Adding network tags '$TAGS' to VM '$VM_NAME'..."
gcloud compute instances add-tags "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --tags="$TAGS"

log_info "Checking if firewall rule '$FIREWALL_RULE_NAME' already exists..."
if gcloud compute firewall-rules describe "$FIREWALL_RULE_NAME" --project="$PROJECT_ID" &>/dev/null; then
  log_info "Firewall rule '$FIREWALL_RULE_NAME' already exists. Exiting."
  exit 0
fi

log_info "Firewall rule '$FIREWALL_RULE_NAME' does not exist. Proceeding with creation."
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

log_success "Firewall rule '$FIREWALL_RULE_NAME' created successfully."

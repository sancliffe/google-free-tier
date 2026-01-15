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
# shellcheck disable=SC1091
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    log_info() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${CYAN}[INFO]${NC} $*"; }
    log_success() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${GREEN}[✅ SUCCESS]${NC} $*"; }
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
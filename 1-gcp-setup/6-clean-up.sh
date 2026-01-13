#!/bin/bash
# cleanup-gcp-setup.sh
# Removes resources created by scripts 1 through 5 in 1-gcp-setup.

set -euo pipefail

# --- Configuration (Matching original scripts) ---
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-west1-a"
VM_NAME="free-tier-vm"
REPO_NAME="gke-apps"
REPO_LOCATION="us-central1"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }

echo "------------------------------------------------------------"
log_info "Starting Cleanup for Project: ${PROJECT_ID}"
echo "------------------------------------------------------------"

# 1. Delete VM Instance (from 1-create-vm.sh)
log_info "Deleting VM instance: ${VM_NAME}..."
gcloud compute instances delete "${VM_NAME}" --zone="${ZONE}" --quiet || true

# 2. Delete Firewall Rules (from 2-open-firewall.sh)
log_info "Deleting firewall rules: allow-http, allow-https..."
gcloud compute firewall-rules delete allow-http allow-https --quiet || true

# 3. Delete Monitoring Resources (from 3-setup-monitoring.sh)
# Note: These require finding the IDs dynamically as they aren't hardcoded in setup
log_info "Deleting Uptime Checks and Alert Policies..."
UPTIME_IDS=$(gcloud monitoring uptime-check-configs list --format="value(name)")
for ID in $UPTIME_IDS; do
    if [[ $(gcloud monitoring uptime-check-configs describe "$ID" --format="value(displayName)") == *"Uptime check for"* ]]; then
        gcloud monitoring uptime-check-configs delete "$ID" --quiet && log_success "Deleted $ID"
    fi
done

ALERT_IDS=$(gcloud monitoring policies list --format="value(name)")
for ID in $ALERT_IDS; do
    if [[ $(gcloud monitoring policies describe "$ID" --format="value(displayName)") == *"Uptime Check Alert"* ]]; then
        gcloud monitoring policies delete "$ID" --quiet && log_success "Deleted $ID"
    fi
done

# 4. Delete Secret Manager Secrets (from 4-create-secrets.sh)
log_info "Deleting secrets..."
SECRETS=(
    "duckdns_token" 
    "email_address" 
    "domain_name" 
    "gcs_bucket_name" 
    "tf_state_bucket" 
    "backup_dir" 
    "billing_account_id"
)
for SECRET in "${SECRETS[@]}"; do
    gcloud secrets delete "${SECRET}" --quiet || true
done

# 5. Delete Artifact Registry Repository (from 5-create-artifact-registry.sh)
log_info "Deleting Artifact Registry: ${REPO_NAME}..."
gcloud artifacts repositories delete "${REPO_NAME}" \
    --location="${REPO_LOCATION}" \
    --quiet || true

echo "------------------------------------------------------------"
log_success "Cleanup Complete!"
echo "------------------------------------------------------------"
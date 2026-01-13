#!/bin/bash
# cleanup-gcp-setup.sh
# Removes resources created by scripts 1 through 5 in 1-gcp-setup.

set -euo pipefail

# --- Configuration (Matching original setup scripts) ---
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-west1-a"
VM_NAME="free-tier-vm"
REPO_NAME="gke-apps"
REPO_LOCATION="us-central1"

# Logging Helpers
log_info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m $*"; }

echo "------------------------------------------------------------"
log_info "Starting Cleanup for Project: ${PROJECT_ID}"
echo "------------------------------------------------------------"

# 1. Delete VM Instance (from 1-create-vm.sh)
log_info "Step 1: Deleting VM instance: ${VM_NAME}..."
gcloud compute instances delete "${VM_NAME}" --zone="${ZONE}" --quiet || log_warn "VM ${VM_NAME} not found or already deleted."

# 2. Delete Firewall Rules (from 2-open-firewall.sh)
log_info "Step 2: Deleting firewall rules: allow-http, allow-https..."
gcloud compute firewall-rules delete allow-http allow-https --quiet || log_warn "Firewall rules not found or already deleted."

# 3. Delete Monitoring Resources (from 3-setup-monitoring.sh)
log_info "Step 3: Deleting Uptime Checks and Alert Policies..."

# Delete Uptime Checks
# Using 'monitoring uptime list-configs' as per updated gcloud CLI choice
UPTIME_IDS=$(gcloud monitoring uptime list-configs --format="value(name)" 2>/dev/null || echo "")
if [[ -n "$UPTIME_IDS" ]]; then
    for ID in $UPTIME_IDS; do
        DISPLAY_NAME=$(gcloud monitoring uptime describe "$ID" --format="value(displayName)" 2>/dev/null || echo "")
        if [[ "$DISPLAY_NAME" == *"Uptime check for"* ]]; then
            gcloud monitoring uptime delete "$ID" --quiet && log_success "Deleted Uptime Check: $DISPLAY_NAME"
        fi
    done
else
    log_info "No uptime checks found."
fi

# Delete Alert Policies
ALERT_IDS=$(gcloud monitoring policies list --format="value(name)" 2>/dev/null || echo "")
if [[ -n "$ALERT_IDS" ]]; then
    for ID in $ALERT_IDS; do
        DISPLAY_NAME=$(gcloud monitoring policies describe "$ID" --format="value(displayName)" 2>/dev/null || echo "")
        if [[ "$DISPLAY_NAME" == *"Uptime Check Alert"* ]]; then
            gcloud monitoring policies delete "$ID" --quiet && log_success "Deleted Alert Policy: $DISPLAY_NAME"
        fi
    done
else
    log_info "No alert policies found."
fi

# 4. Delete Secret Manager Secrets (from 4-create-secrets.sh)
log_info "Step 4: Deleting secrets..."
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
    if gcloud secrets describe "${SECRET}" &>/dev/null; then
        gcloud secrets delete "${SECRET}" --quiet && log_success "Deleted secret: ${SECRET}"
    else
        log_info "Secret ${SECRET} not found."
    fi
done

# 5. Delete Artifact Registry Repository (from 5-create-artifact-registry.sh)
log_info "Step 5: Deleting Artifact Registry: ${REPO_NAME}..."
if gcloud artifacts repositories describe "${REPO_NAME}" --location="${REPO_LOCATION}" &>/dev/null; then
    gcloud artifacts repositories delete "${REPO_NAME}" \
        --location="${REPO_LOCATION}" \
        --quiet && log_success "Deleted repository: ${REPO_NAME}"
else
    log_info "Repository ${REPO_NAME} not found."
fi

echo "------------------------------------------------------------"
log_success "Cleanup Process Finished!"
echo "------------------------------------------------------------"
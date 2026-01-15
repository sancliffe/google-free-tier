#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# shellcheck source=/dev/null
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
    log_info() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${CYAN}[INFO]${NC} $*"; }
    log_error() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${RED}[ERROR]${NC} $*" >&2; }
    log_success() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${GREEN}[✅ SUCCESS]${NC} $*"; }
fi

if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"

log_info "Validating GCP Setup for project: $PROJECT_ID"

# Verify required tools
for tool in gcloud jq; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "Required tool '$tool' is not installed."
        exit 1
    fi
done

echo ""

PASS=0
FAIL=0

# Check VM
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
  log_success "VM '$VM_NAME' exists"
  PASS=$((PASS + 1))
else
  log_error "VM '$VM_NAME' not found"
  FAIL=$((FAIL + 1))
fi

# Check Firewall
if gcloud compute firewall-rules describe "$FIREWALL_RULE_NAME" --project="$PROJECT_ID" &>/dev/null; then
  log_success "Firewall rule '$FIREWALL_RULE_NAME' exists"
  PASS=$((PASS + 1))
else
  log_error "Firewall rule '$FIREWALL_RULE_NAME' not found"
  FAIL=$((FAIL + 1))
fi

# Check Artifact Registry
if gcloud artifacts repositories describe "$REPO_NAME" --location="$REPO_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
  log_success "Artifact Registry '$REPO_NAME' exists"
  PASS=$((PASS + 1))
else
  log_error "Artifact Registry '$REPO_NAME' not found"
  FAIL=$((FAIL + 1))
fi

# Check individual Secrets
declare -a EXPECTED_SECRETS=(
  "duckdns_token" "email_address" "domain_name" "gcs_bucket_name"
  "tf_state_bucket" "backup_dir" "billing_account_id"
)

for secret_name in "${EXPECTED_SECRETS[@]}"; do
  if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null; then
    log_success "Secret '$secret_name' exists"
    PASS=$((PASS + 1))
  else
    log_error "Secret '$secret_name' not found"
    FAIL=$((FAIL + 1))
  fi
done

# Check Monitoring
UPTIME_COUNT=$(gcloud monitoring uptime list-configs --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
if [[ $UPTIME_COUNT -gt 0 ]]; then
  log_success "Found $UPTIME_COUNT uptime check(s)"
  PASS=$((PASS + 1))
else
  log_error "No uptime checks found"
  FAIL=$((FAIL + 1))
fi

# Check GCS Backup Bucket
if gcloud storage buckets describe "$GCS_BUCKET_NAME" --project="$PROJECT_ID" &>/dev/null; then
  log_success "GCS Backup Bucket '$GCS_BUCKET_NAME' exists"
  PASS=$((PASS + 1))
else
  log_error "GCS Backup Bucket '$GCS_BUCKET_NAME' not found"
  FAIL=$((FAIL + 1))
fi

# Check GCS Terraform State Bucket
if gcloud storage buckets describe "$TF_STATE_BUCKET" --project="$PROJECT_ID" &>/dev/null; then
  log_success "GCS Terraform State Bucket '$TF_STATE_BUCKET' exists"
  PASS=$((PASS + 1))
else
  log_error "GCS Terraform State Bucket '$TF_STATE_BUCKET' not found"
  FAIL=$((FAIL + 1))
fi

# Check Monitoring Notification Channel
# Assumes EMAIL_ADDRESS is defined in config.sh
if gcloud monitoring notification-channels list --project="$PROJECT_ID" --format="json" | jq -e ".[] | select(.type == \"email\" and .labels.email_address == \"$EMAIL_ADDRESS\")" &>/dev/null; then
  log_success "Monitoring Notification Channel for '$EMAIL_ADDRESS' exists"
  PASS=$((PASS + 1))
else
  log_error "Monitoring Notification Channel for '$EMAIL_ADDRESS' not found"
  FAIL=$((FAIL + 1))
fi



echo ""
log_info "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
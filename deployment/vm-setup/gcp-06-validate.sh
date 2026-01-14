#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# shellcheck source=/dev/null
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
    log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }
    log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [✅ SUCCESS] $*"; }
fi

if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"

log_info "Validating GCP Setup for project: $PROJECT_ID"
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

# Check Secrets
SECRET_COUNT=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
if [[ $SECRET_COUNT -gt 0 ]]; then
  log_success "Found $SECRET_COUNT secrets"
  PASS=$((PASS + 1))
else
  log_error "No secrets found"
  FAIL=$((FAIL + 1))
fi

# Check Monitoring
UPTIME_COUNT=$(gcloud monitoring uptime list-configs --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
if [[ $UPTIME_COUNT -gt 0 ]]; then
  log_success "Found $UPTIME_COUNT uptime check(s)"
  PASS=$((PASS + 1))
else
  log_error "No uptime checks found"
  FAIL=$((FAIL + 1))
fi

echo ""
log_info "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
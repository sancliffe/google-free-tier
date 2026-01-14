#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"

echo "Validating GCP Setup for project: $PROJECT_ID"
echo ""

PASS=0
FAIL=0

# Check VM
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ VM '$VM_NAME' exists"
  PASS=$((PASS + 1))
else
  echo "✗ VM '$VM_NAME' not found"
  FAIL=$((FAIL + 1))
fi

# Check Firewall
if gcloud compute firewall-rules describe "$FIREWALL_RULE_NAME" --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ Firewall rule '$FIREWALL_RULE_NAME' exists"
  PASS=$((PASS + 1))
else
  echo "✗ Firewall rule '$FIREWALL_RULE_NAME' not found"
  FAIL=$((FAIL + 1))
fi

# Check Artifact Registry
if gcloud artifacts repositories describe "$REPO_NAME" --location="$REPO_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ Artifact Registry '$REPO_NAME' exists"
  PASS=$((PASS + 1))
else
  echo "✗ Artifact Registry '$REPO_NAME' not found"
  FAIL=$((FAIL + 1))
fi

# Check Secrets
SECRET_COUNT=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
if [[ $SECRET_COUNT -gt 0 ]]; then
  echo "✓ Found $SECRET_COUNT secrets"
  PASS=$((PASS + 1))
else
  echo "✗ No secrets found"
  FAIL=$((FAIL + 1))
fi

# Check Monitoring
UPTIME_COUNT=$(gcloud monitoring uptime list-configs --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
if [[ $UPTIME_COUNT -gt 0 ]]; then
  echo "✓ Found $UPTIME_COUNT uptime check(s)"
  PASS=$((PASS + 1))
else
  echo "✗ No uptime checks found"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
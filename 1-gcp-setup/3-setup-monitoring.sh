#!/bin/bash
set -euo pipefail

# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arguments passed from setup-gcp.sh
VM_NAME="$1"
ZONE="$2"
EMAIL_ADDRESS="$3"
DISPLAY_NAME="$4"
DOMAIN="$5"
PROJECT_ID="$6"

# Source common functions if available
if [[ -f "${SCRIPT_DIR}/../2-host-setup/common.sh" ]]; then
    source "${SCRIPT_DIR}/../2-host-setup/common.sh"
else
    # Minimal logging functions if common.sh not available
    log_info() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [INFO] $*"; }
    log_success() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [SUCCESS] $*"; }
    log_error() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [ERROR] $*" >&2; }
    log_warn() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [WARN] $*"; }
fi

echo "------------------------------------------------------------"
log_info "Starting GCP Monitoring Setup"
echo "------------------------------------------------------------"
log_info "Active Project: ${PROJECT_ID}"

# Refresh authentication
log_info "Refreshing authentication tokens..."
gcloud auth application-default login --quiet 2>/dev/null || true

# Verify VM has monitoring scopes
log_info "Verifying VM Access Scopes..."
if gcloud compute instances describe "${VM_NAME}" --zone="${ZONE}" --format="get(serviceAccounts[0].scopes)" 2>/dev/null | grep -q "monitoring"; then
    log_success "Scopes verified."
else
    log_warn "VM may need monitoring.write scope."
fi

echo "------------------------------------------------------------"

# Step 1: Create or Get Notification Channel
log_info "Step 1: Checking for existing Notification Channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels list \
  --filter="displayName=\"${DISPLAY_NAME}\" AND type=\"email\"" \
  --format="value(name)")

if [[ -z "${CHANNEL_ID}" ]]; then
  log_info "No existing channel found. Creating new channel..."
  CHANNEL_ID=$(gcloud alpha monitoring channels create \
    --display-name="${DISPLAY_NAME}" \
    --type=email \
    --channel-labels=email_address="${EMAIL_ADDRESS}" \
    --format="value(name)")
  log_success "Created Channel: ${CHANNEL_ID}"
  log_warn "Check ${EMAIL_ADDRESS} for a verification email before proceeding."
  read -rp "Press [Enter] to continue after verifying..."
else
  log_success "Found existing channel: ${CHANNEL_ID}"
fi
# Step 2: Create or Get Uptime Check
log_info "Step 2: Checking for existing Uptime Check for ${DOMAIN}..."
# The gcloud command for this is not stable across versions, so we use grep.
UPTIME_CHECK_ID=$(gcloud monitoring uptime list-configs \
  --project="${PROJECT_ID}" \
  --format='value(name,displayName)' | \
  grep "Uptime check for ${DOMAIN}" | \
  awk '{print $1}' || true)

if [[ -z "${UPTIME_CHECK_ID}" ]]; then
  log_info "No existing uptime check found. Creating new uptime check via API..."

  # Install jq if not present (for JSON parsing)
  if ! command -v jq &> /dev/null; then
      log_info "Installing jq for JSON parsing..."
      sudo apt-get update -qq && sudo apt-get install -y jq -qq
  fi

  # Create a temporary JSON file for the uptime check configuration
  UPTIME_CONFIG=$(mktemp)
  cat > "${UPTIME_CONFIG}" << EOF
{
  "displayName": "Uptime check for ${DOMAIN}",
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "host": "${DOMAIN}"
    }
  },
  "httpCheck": {
    "path": "/",
    "port": 443,
    "useSsl": true,
    "validateSsl": true
  },
  "period": "300s",
  "timeout": "10s"
}
EOF

  # Get access token
  ACCESS_TOKEN=$(gcloud auth print-access-token)

  # Create uptime check via API
  UPTIME_RESPONSE=$(curl -s -X POST \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/uptimeCheckConfigs" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @"${UPTIME_CONFIG}")

  rm -f "${UPTIME_CONFIG}"

  # Check for errors in response
  if echo "${UPTIME_RESPONSE}" | jq -e '.error' > /dev/null 2>&1; then
      log_error "API Error: $(echo "${UPTIME_RESPONSE}" | jq -r '.error.message')"
      log_error "Full response: ${UPTIME_RESPONSE}"
      exit 1
  fi

  # Extract the uptime check name/ID using jq
  UPTIME_CHECK_ID=$(echo "${UPTIME_RESPONSE}" | jq -r '.name // empty')

  if [[ -z "${UPTIME_CHECK_ID}" ]]; then
      log_error "Failed to create uptime check. Response: ${UPTIME_RESPONSE}"
      exit 1
  fi
  log_success "Created Uptime Check: ${UPTIME_CHECK_ID}"
else
    log_success "Found existing uptime check: ${UPTIME_CHECK_ID}"
fi


# Step 3: Create or Get Alert Policy
log_info "Step 3: Checking for existing Alert Policy for ${DOMAIN}..."
ALERT_POLICY_ID=$(gcloud alpha monitoring policies list \
  --filter="displayName=\"Uptime Check Alert for ${DOMAIN}\"" \
  --format="value(name)")

if [[ -z "${ALERT_POLICY_ID}" ]]; then
  log_info "No existing alert policy found. Creating new alert policy..."
  CHECK_ID_ONLY=$(basename "${UPTIME_CHECK_ID}")

  ALERT_CONFIG=$(mktemp)
  cat > "${ALERT_CONFIG}" << EOF
{
  "displayName": "Uptime Check Alert for ${DOMAIN}",
  "conditions": [
    {
      "displayName": "Uptime check failed",
      "conditionThreshold": {
        "filter": "metric.type=\\"monitoring.googleapis.com/uptime_check/check_passed\\" AND resource.type=\\"uptime_url\\" AND metric.label.check_id=\\"${CHECK_ID_ONLY}\\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE"
          }
        ]
      }
    }
  ],
  "notificationChannels": [
    "${CHANNEL_ID}"
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR"
}
EOF

  ALERT_POLICY_ID=$(gcloud alpha monitoring policies create \
    --policy-from-file="${ALERT_CONFIG}" \
    --format="value(name)")

  rm -f "${ALERT_CONFIG}"
  log_success "Created Alert Policy: ${ALERT_POLICY_ID}"
else
    log_success "Found existing alert policy: ${ALERT_POLICY_ID}"
fi

echo "------------------------------------------------------------"
log_success "Monitoring Setup Complete!"
echo "------------------------------------------------------------"
log_info "Summary:"
log_info "  • Notification Channel: ${CHANNEL_ID}"
log_info "  • Uptime Check: ${UPTIME_CHECK_ID}"
log_info "  • Alert Policy: ${ALERT_POLICY_ID}"
log_info "  • Monitoring Domain: https://${DOMAIN}"
echo "------------------------------------------------------------"
log_info "🎯 Quick Verification Steps:"
log_info ""
log_info "1. Check monitoring dashboard:"
log_info "   https://console.cloud.google.com/monitoring/uptime?project=${PROJECT_ID}"
log_info ""
log_info "2. Verify email notifications:"
log_info "   - Check ${EMAIL_ADDRESS} for verification email"
log_info "   - Click the verification link in the email"
log_info ""
log_info "3. Test uptime check (after VM setup):"
log_info "   curl -I https://${DOMAIN}"
log_info ""
log_info "4. View alert policies:"
log_info "   gcloud alpha monitoring policies list --project=${PROJECT_ID}"
echo "------------------------------------------------------------"
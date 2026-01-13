#!/bin/bash
set -euo pipefail

# Source common functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../2-host-setup/common.sh" ]]; then
    source "${SCRIPT_DIR}/../2-host-setup/common.sh"
else
    # Minimal logging functions if common.sh not available
    log_info() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [INFO] $*"; }
    log_success() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [SUCCESS] $*"; }
    log_error() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [ERROR] $*" >&2; }
    log_warn() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [WARN] $*"; }
fi

# Configuration
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

echo "------------------------------------------------------------"
log_info "Starting GCP Monitoring Setup"
echo "------------------------------------------------------------"
log_info "Active Project: ${PROJECT_ID}"

# Refresh authentication
log_info "Refreshing authentication tokens..."
gcloud auth application-default login --quiet 2>/dev/null || true

# Verify VM has monitoring scopes
log_info "Verifying VM Access Scopes..."
if gcloud compute instances describe "$(hostname)" --zone="$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | cut -d/ -f4)" --format="get(serviceAccounts[0].scopes)" 2>/dev/null | grep -q "monitoring"; then
    log_success "Scopes verified."
else
    log_warn "VM may need monitoring.write scope."
fi

echo "------------------------------------------------------------"
# Prompt for user input
read -rp "Enter notification email: " EMAIL_ADDRESS
read -rp "Enter notification display name (e.g. Admin): " DISPLAY_NAME
read -rp "Enter domain to monitor (e.g. example.com): " DOMAIN
echo "------------------------------------------------------------"

# Step 1: Create Notification Channel
log_info "Step 1: Creating Notification Channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --display-name="${DISPLAY_NAME}" \
  --type=email \
  --channel-labels=email_address="${EMAIL_ADDRESS}" \
  --format="value(name)")

log_success "Created Channel: ${CHANNEL_ID}"
log_warn "Check ${EMAIL_ADDRESS} for a verification email before proceeding."
read -rp "Press [Enter] to continue..."

# Step 2: Create Uptime Check using API
log_info "Step 2: Creating Uptime Check for ${DOMAIN}..."

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

# Step 3: Create Alert Policy using API
log_info "Step 3: Creating Alert Policy for Uptime Check..."

# Extract just the check_id from the full path
CHECK_ID_ONLY=$(basename "${UPTIME_CHECK_ID}")

ALERT_CONFIG=$(mktemp)
cat > "${ALERT_CONFIG}" << EOF
{
  "displayName": "Uptime Check Alert for ${DOMAIN}",
  "conditions": [
    {
      "displayName": "Uptime check failed",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${CHECK_ID_ONLY}\"",
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

# Create alert policy via API
ALERT_RESPONSE=$(curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/alertPolicies" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @"${ALERT_CONFIG}")

rm -f "${ALERT_CONFIG}"

# Check for errors in response
if echo "${ALERT_RESPONSE}" | jq -e '.error' > /dev/null 2>&1; then
    log_error "API Error: $(echo "${ALERT_RESPONSE}" | jq -r '.error.message')"
    log_error "Full response: ${ALERT_RESPONSE}"
    exit 1
fi

# Extract alert policy name using jq
ALERT_POLICY_ID=$(echo "${ALERT_RESPONSE}" | jq -r '.name // empty')

if [[ -z "${ALERT_POLICY_ID}" ]]; then
    log_error "Failed to create alert policy. Response: ${ALERT_RESPONSE}"
    exit 1
fi

log_success "Created Alert Policy: ${ALERT_POLICY_ID}"

echo "------------------------------------------------------------"
log_success "Monitoring Setup Complete!"
echo "------------------------------------------------------------"
log_info "Summary:"
log_info "  • Notification Channel: ${CHANNEL_ID}"
log_info "  • Uptime Check: ${UPTIME_CHECK_ID}"
log_info "  • Alert Policy: ${ALERT_POLICY_ID}"
log_info "  • Monitoring Domain: https://${DOMAIN}"
echo "------------------------------------------------------------"
log_info "Next Steps:"
log_info "  1. Verify email notification channel"
log_info "  2. Check uptime check status in Cloud Console"
log_info "  3. Test alert by taking site offline briefly"
echo "------------------------------------------------------------"
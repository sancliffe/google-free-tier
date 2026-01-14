#!/bin/bash
set -euo pipefail

# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Default values
ZONE="us-west1-a"
VM_NAME="free-tier-vm"
EMAIL_ADDRESS=""
DISPLAY_NAME="Admin"
DOMAIN=""
PROJECT_ID=""

# Source config file if it exists
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=config.sh
    source "${CONFIG_FILE}"
fi

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

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)        EMAIL_ADDRESS="$2"; shift 2;;
        --display-name) DISPLAY_NAME="$2"; shift 2;;
        --domain)       DOMAIN="$2"; shift 2;;
        --project-id)   PROJECT_ID="$2"; shift 2;;
        *)              echo "Unknown option: $1"; exit 1;;
    esac
done

# If PROJECT_ID is not set by args or config, get it from gcloud
if [[ -z "${PROJECT_ID}" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
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
# Prompt for user input if not provided via args or config
if [[ -z "${EMAIL_ADDRESS}" ]]; then
    read -rp "Enter notification email: " EMAIL_ADDRESS
fi
if [[ -z "${DISPLAY_NAME}" ]]; then
    read -rp "Enter notification display name (e.g. Admin): " DISPLAY_NAME
fi
if [[ -z "${DOMAIN}" ]]; then
    read -rp "Enter domain to monitor (e.g. example.com): " DOMAIN
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
UPTIME_CHECK_ID=$(gcloud monitoring uptime-checks list \
  --filter="displayName=\"Uptime check for ${DOMAIN}\"" \
  --format="value(name)")

if [[ -z "${UPTIME_CHECK_ID}" ]]; then
  log_info "No existing uptime check found. Creating new uptime check..."
  UPTIME_CHECK_FULL_NAME=$(gcloud monitoring uptime-checks create \
    --display-name="Uptime check for ${DOMAIN}" \
    --resource-type="uptime_url" \
    --resource-labels="host=${DOMAIN}" \
    --http-check-path="/" \
    --http-check-port=443 \
    --http-check-use-ssl \
    --http-check-validate-ssl \
    --period=300s \
    --timeout=10s \
    --format="value(name)")
    UPTIME_CHECK_ID="$UPTIME_CHECK_FULL_NAME"
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
log_info "Next Steps:"
log_info "  1. Verify email notification channel"
log_info "  2. Check uptime check status in Cloud Console"
log_info "  3. Test alert by taking site offline briefly"
echo "------------------------------------------------------------"
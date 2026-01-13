#!/bin/bash
#
# This script guides you through setting up GCP Monitoring (Uptime Checks & Alerts).

# --- Strict Mode & Helpers ---
set -euo pipefail

# Enhanced Logging Colors
COL_RESET="\033[0m"
COL_INFO="\033[0;34m"
COL_SUCCESS="\033[0;32m"
COL_WARN="\033[0;33m"
COL_ERROR="\033[0;31m"
COL_BOLD="\033[1m"

_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -e "${timestamp} ${color}${COL_BOLD}[${level}]${COL_RESET} ${message}"
}

log_info()    { _log "INFO"    "$COL_INFO"    "$1"; }
log_success() { _log "SUCCESS" "$COL_SUCCESS" "$1"; }
log_warn()    { _log "WARN"    "$COL_WARN"    "$1"; }
log_error()   { _log "ERROR"   "$COL_ERROR"   "$1"; }

hr() { echo -e "${COL_INFO}------------------------------------------------------------${COL_RESET}"; }

# --- Pre-flight Checks ---
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud command not found. Please install the Google Cloud SDK."
    exit 1
fi

# --- Main Logic ---
main() {
    hr
    log_info "Starting GCP Monitoring Setup"
    hr
    
    # 1. DYNAMIC PROJECT ID LOOKUP
    local project_id
    project_id="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    
    if [[ -z "${project_id}" ]]; then
        log_error "Project ID could not be determined. Run 'gcloud config set project [ID]'"
        exit 1
    fi
    log_info "Active Project: ${COL_BOLD}${project_id}${COL_RESET}"

    # 2. CREDENTIAL REFRESH
    log_info "Refreshing authentication tokens..."
    gcloud auth revoke --all --quiet > /dev/null 2>&1 || true
    gcloud config set auth/access_token_file "" --quiet > /dev/null 2>&1 || true

    # 3. SCOPE CHECK
    log_info "Verifying VM Access Scopes..."
    local scopes
    scopes=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/scopes)
    
    if [[ ! "$scopes" == *"monitoring"* ]] && [[ ! "$scopes" == *"cloud-platform"* ]]; then
        log_error "Insufficient Scopes. VM cannot write to Monitoring API."
        log_info "Run this from Cloud Shell: gcloud compute instances set-service-account $(hostname) --scopes=cloud-platform --zone=[ZONE]"
        exit 1
    fi
    log_success "Scopes verified."

    # 4. USER INPUT
    hr
    read -r -p "Enter notification email: " email
    read -r -p "Enter notification display name (e.g. Admin): " display_name
    read -r -p "Enter domain to monitor (e.g. example.com): " domain
    hr

    # 5. NOTIFICATION CHANNEL
    log_info "Step 1: Creating Notification Channel..."
    local channel_name
    channel_name=$(gcloud beta monitoring channels create \
        --project="${project_id}" \
        --display-name="${display_name}" \
        --description="Alerting channel for ${domain}" \
        --type=email \
        --channel-labels=email_address="${email}" \
        --format='value(name)')

    log_success "Created Channel: ${channel_name}"
    log_warn "Check ${email} for a verification email before proceeding."
    read -r -p "Press [Enter] to continue..."

    # 6. UPTIME CHECK
    # Fix: Rearranged arguments to put 'http' and 'ID' in the order some gcloud versions prefer
    log_info "Step 2: Creating Uptime Check for ${domain}..."
    local check_id="uptime-check-${domain//./-}"
    
    gcloud monitoring uptime create http "${check_id}" \
        --project="${project_id}" \
        --display-name="Uptime check for ${domain}" \
        --resource-type="uptime-url" \
        --resource-labels=host="${domain}",project_id="${project_id}" \
        --check-interval="300s"

    log_success "Created Uptime Check: ${check_id}"

    # 7. ALERTING POLICY
    log_info "Step 3: Creating Alerting Policy..."
    local filter="metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.check_id=\"${check_id}\""

    local policy_name
    policy_name=$(gcloud monitoring policies create \
        --project="${project_id}" \
        --display-name="[${domain}] Site Down Alert" \
        --notification-channels="${channel_name}" \
        --condition-display-name="Uptime check failed" \
        --condition-filter="${filter}" \
        --condition-duration="60s" \
        --condition-trigger-count=1 \
        --condition-aggregator=count \
        --documentation="The uptime check for ${domain} has failed. Check the VM and Web Server status." \
        --format='value(name)')

    log_success "Created Policy: ${policy_name}"

    hr
    log_success "Setup Complete! Monitoring is now active."
    log_info "View your dashboard at: https://console.cloud.google.com/monitoring/uptime?project=${project_id}"
    hr
}

main
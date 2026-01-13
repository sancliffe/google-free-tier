#!/bin/bash
#
# This script guides you through setting up monitoring for your VM.

# --- Strict Mode & Helpers ---
set -euo pipefail

_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if [[ "$level" == "ERROR" ]]; then
        echo -e "${timestamp} [${level}] ${color}${message}\033[0m" >&2
    else
        echo -e "${timestamp} [${level}] ${color}${message}\033[0m"
    fi
}

log_info() { _log "INFO" "" "$1"; }
log_success() { _log "✅" "\033[0;32m" "$1"; }
log_warn() { _log "WARN" "\033[0;33m" "$1"; }
log_error() { _log "ERROR" "\033[0;31m" "$1"; }

# --- Pre-flight Checks ---
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud command not found."
    log_info "Please install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# --- Main Logic ---
main() {
    log_info "--- GCP Monitoring Setup ---" 
    
    echo -e "\033[0;33mWARNING: The information you enter will be stored in your shell's history.\033[0m"
    echo -e "\033[0;33mTo avoid this, you can run the script in a new shell with 'bash' and exit immediately after.\033[0m"

    # DYNAMIC PROJECT ID LOOKUP
    local project_id
    project_id="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    
    if [[ -z "${project_id}" ]]; then
        log_error "Project ID could not be determined."
        log_info "Run 'gcloud config set project [PROJECT_ID]' or set GOOGLE_CLOUD_PROJECT environment variable."
        exit 1
    fi
    log_info "Operating in project: ${project_id}"

    # CACHE CLEARING: Force gcloud to pick up updated Scopes/IAM roles
    log_info "Refreshing gcloud credentials cache..."
    gcloud auth revoke --all --quiet > /dev/null 2>&1 || true
    gcloud config set auth/access_token_file "" --quiet > /dev/null 2>&1 || true

    # SCOPE CHECK
    log_info "Checking VM access scopes..."
    local scopes
    scopes=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/scopes)
    
    if [[ ! "$scopes" == *"monitoring"* ]] && [[ ! "$scopes" == *"cloud-platform"* ]]; then
        log_error "INSUFFICIENT ACCESS SCOPES"
        log_warn "Your VM does not have permission to create Monitoring resources."
        log_info "From Cloud Shell, run: gcloud compute instances set-service-account $(hostname) --scopes=cloud-platform --zone=[YOUR_ZONE]"
        exit 1
    fi

    local email
    read -r -p "Enter the email address for alert notifications: " email
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format"
        exit 1
    fi

    local display_name
    read -r -p "Enter a display name for this notification channel (e.g., 'Admin On-Call'): " display_name

    local domain
    read -r -p "Enter the full domain to monitor (e.g., 'my.duckdns.org'): " domain
    
    log_info "Creating email notification channel for ${email}..."
    local channel_name
    channel_name=$(gcloud beta monitoring channels create \
        --project="${project_id}" \
        --display-name="${display_name}" \
        --description="Email channel for VM alerts" \
        --type=email \
        --channel-labels=email_address="${email}" \
        --format='value(name)')

    if [[ -z "${channel_name}" ]]; then
        log_error "Failed to create notification channel."
        exit 1
    fi
    log_success "Notification channel created: ${channel_name}"
    
    log_warn "A verification email has been sent to ${email}."
    log_warn "If it doesn't arrive, check Spam/Promotions or trigger it manually in GCP Console."
    read -r -p "Press [Enter] after you have clicked the verification link (if received)..."

    # FIX: Corrected syntax for Uptime Check creation
    log_info "Creating HTTP uptime check for ${domain}..."
    local check_id="uptime-check-${domain//./-}"
    gcloud monitoring uptime create http "${check_id}" \
        --project="${project_id}" \
        --display-name="Uptime check for ${domain}" \
        --resource-type="uptime-url" \
        --resource-labels=host="${domain}",project_id="${project_id}" \
        --check-interval=300

    log_success "Uptime check created: ${check_id}"

    log_info "Creating alerting policy..."
    # FIX: Refined filter to target the specific check ID
    local filter="metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.check_id=\"${check_id}\""

    local policy_name
    policy_name=$(gcloud monitoring policies create \
        --project="${project_id}" \
        --display-name="[${domain}] Site Down" \
        --notification-channels="${channel_name}" \
        --condition-display-name="Uptime check failed on ${domain}" \
        --condition-filter="${filter}" \
        --condition-duration="60s" \
        --condition-trigger-count=1 \
        --condition-aggregator=count \
        --documentation="The uptime check for https://${domain} failed. The server may be down or misconfigured." \
        --format='value(name)')

    if [[ -z "${policy_name}" ]]; then
        log_error "Failed to create alerting policy."
        exit 1
    fi
    log_success "Alerting policy created: ${policy_name}"

    log_info "------------------------------"
    log_success "Monitoring setup complete!"
    log_info "You will now receive an email at ${email} if https://${domain} is down."
}

main
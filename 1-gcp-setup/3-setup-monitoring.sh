#!/bin/bash
#
# This script guides you through setting up monitoring for your VM.
# It will create:
#   1. A notification channel to send alerts to your email.
#   2. An uptime check to monitor your website's availability.
#   3. An alerting policy to notify you if your site goes down.
#
# Run this script from your local machine, not the VM.

# --- Strict Mode & Helpers ---
set -euo pipefail

_log_prefix() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') $1"
}
log_info() { echo -e "$(_log_prefix "INFO") $1"; }
log_success() { echo -e "$(_log_prefix "✅") \033[0;32m$1\033[0m"; }
log_warn() { echo -e "$(_log_prefix "WARN") \033[0;33m$1\033[0m"; }
log_error() { echo -e "$(_log_prefix "❌") \033[0;31m$1\033[0m" >&2; }

# --- Pre-flight Checks ---
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud command not found."
    log_info "Please install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# --- Main Logic ---
main() {
    log_info "--- GCP Monitoring Setup ---" 
    
    # --- 1. Get User Details ---
    local project_id
    project_id=$(gcloud config get-value project)
    log_info "Operating in project: ${project_id}"

    local email
    read -p "Enter the email address for alert notifications: " email

    local display_name
    read -p "Enter a display name for this notification channel (e.g., 'Admin On-Call'): " display_name

    local domain
    read -p "Enter the full domain to monitor (e.g., 'my.duckdns.org'): " domain
    
    # --- 2. Create Notification Channel ---
    log_info "Creating email notification channel for ${email}..."
    
    # `gcloud ... --format='value(name)'` prints only the 'name' field of the result.
    local channel_name
    channel_name=$(gcloud beta monitoring channels create \
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
    log_warn "You must click the link in the email before you can receive alerts."
    read -p "Press [Enter] after you have clicked the verification link..."

    # --- 3. Create Uptime Check ---
    log_info "Creating HTTP uptime check for https://${domain}..."
    local uptime_check_id
    uptime_check_id=$(gcloud monitoring uptime-checks create http "https://${domain}" \
        --display-name="Uptime check for ${domain}" \
        --format='value(name)')

    if [[ -z "${uptime_check_id}" ]]; then
        log_error "Failed to create uptime check."
        exit 1
    fi
    log_success "Uptime check created: ${uptime_check_id}"

    # --- 4. Create Alerting Policy ---
    log_info "Creating alerting policy..."
    
    # The condition filter looks for the uptime check metric associated with our check ID.
    local filter
    filter="metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.check_id=\"${uptime_check_id##*/}\""

    local policy_name
    policy_name=$(gcloud monitoring policies create \
        --display-name="[${domain}] Site Down" \
        --notification-channels="${channel_name}" \
        --condition-display-name="Uptime check failed on ${domain}" \
        --condition-filter="${filter}" \
        --condition-duration=\"300s\" \
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
    log_info "You will now receive an email at ${email} if https://${domain} is down for more than 5 minutes."
}

main

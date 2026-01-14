#!/bin/bash
# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize variables to be populated from arguments
DUCKDNS_TOKEN=""
EMAIL_ADDRESS=""
DOMAIN_NAME=""
GCS_BUCKET_NAME=""
TF_STATE_BUCKET=""
BACKUP_DIR="/var/www/html"
BILLING_ACCOUNT_ID=""
PROJECT_ID=""

# Source common functions if available
if [[ -f "${SCRIPT_DIR}/./common.sh" ]]; then
    source "${SCRIPT_DIR}/./common.sh"
else
    log_info() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [INFO] $*"; }
    log_success() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [SUCCESS] $*"; }
    log_error() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [ERROR] $*" >&2; }
    log_warn() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [WARN] $*"; }
fi

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create Google Cloud Secret Manager secrets for the project.

OPTIONS:
    -t, --duckdns-token TOKEN          DuckDNS token
    -e, --email EMAIL                  Email address for SSL notifications
    -d, --domain DOMAIN                Domain name (e.g., mydomain.duckdns.org)
    -b, --bucket BUCKET                GCS backup bucket name
    -s, --tf-state-bucket BUCKET       Terraform state bucket name
    -r, --backup-dir DIR               Directory to backup (default: /var/www/html)
    -a, --billing-account ID           GCP billing account ID
    --project-id ID                    GCP project ID
    -h, --help                         Show this help message
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--duckdns-token)    DUCKDNS_TOKEN="$2"; shift 2;;
        -e|--email)            EMAIL_ADDRESS="$2"; shift 2;;
        -d|--domain)           DOMAIN_NAME="$2"; shift 2;;
        -b|--bucket)           GCS_BUCKET_NAME="$2"; shift 2;;
        -s|--tf-state-bucket)  TF_STATE_BUCKET="$2"; shift 2;;
        -r|--backup-dir)       BACKUP_DIR="$2"; shift 2;;
        -a|--billing-account)  BILLING_ACCOUNT_ID="$2"; shift 2;;
        --project-id)          PROJECT_ID="$2"; shift 2;;
        -h|--help)             show_usage; exit 0;;
        *)                     log_error "Unknown option: $1"; show_usage; exit 1;;
    esac
done

if [[ -z "${PROJECT_ID}" ]]; then
    log_error "No active GCP project ID provided. Use --project-id or ensure 'gcloud config set project PROJECT_ID' has been run."
    exit 1
fi

echo "============================================================"
log_info "Creating Secrets in Project: ${PROJECT_ID}"
echo "============================================================"

TOTAL_SECRETS=7
CURRENT_SECRET=0

# Function to create or update a secret
create_secret() {
    local secret_name="$1"
    local secret_value="$2"

    CURRENT_SECRET=$((CURRENT_SECRET + 1))

    if [[ -z "${secret_value}" ]]; then
        log_info "[$CURRENT_SECRET/$TOTAL_SECRETS] Skipping '${secret_name}' (empty value)"
        return 0
    fi

    # Check if secret exists
    if gcloud secrets describe "${secret_name}" --project="${PROJECT_ID}" &>/dev/null; then
        # Secret exists, check if the latest version matches
        local latest_value
        latest_value=$(gcloud secrets versions access latest --secret="${secret_name}" --project="${PROJECT_ID}" 2>/dev/null || echo "")

        if [[ "${latest_value}" == "${secret_value}" ]]; then
            log_info "[$CURRENT_SECRET/$TOTAL_SECRETS] Secret '${secret_name}' is already up-to-date."
        else
            log_warn "[$CURRENT_SECRET/$TOTAL_SECRETS] Secret '${secret_name}' exists but has a different value. Adding new version..."
            echo -n "${secret_value}" | gcloud secrets versions add "${secret_name}" --data-file=- --project="${PROJECT_ID}"
            log_success "[$CURRENT_SECRET/$TOTAL_SECRETS] Updated '${secret_name}'"
        fi
    else
        log_info "[$CURRENT_SECRET/$TOTAL_SECRETS] Creating secret: ${secret_name}"
        # FIX: Standardized quote handling for replication policy and labels to avoid gcloud parsing errors
        echo -n "${secret_value}" | gcloud secrets create "${secret_name}" \
            --data-file=- \
            --replication-policy="automatic" \
            --labels="managed-by=script" \
            --project="${PROJECT_ID}"
        log_success "[$CURRENT_SECRET/$TOTAL_SECRETS] Created '${secret_name}'"
    fi
}

echo ""
echo "============================================================"
log_info "Creating secrets with provided values..."
echo "============================================================"

create_secret "duckdns_token" "${DUCKDNS_TOKEN}"
create_secret "email_address" "${EMAIL_ADDRESS}"
create_secret "domain_name" "${DOMAIN_NAME}"
create_secret "gcs_bucket_name" "${GCS_BUCKET_NAME}"
create_secret "tf_state_bucket" "${TF_STATE_BUCKET}"
create_secret "backup_dir" "${BACKUP_DIR}"
create_secret "billing_account_id" "${BILLING_ACCOUNT_ID}"

echo ""
echo "============================================================"
log_success "Secrets creation complete!"
echo "============================================================"
log_info "View secrets: gcloud secrets list --project=${PROJECT_ID}"
log_info "Read secret: gcloud secrets versions access latest --secret=SECRET_NAME --project=${PROJECT_ID}"
echo "============================================================"
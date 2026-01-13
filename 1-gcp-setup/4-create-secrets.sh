#!/bin/bash
set -euo pipefail

# Source common functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../2-host-setup/common.sh" ]]; then
    source "${SCRIPT_DIR}/../2-host-setup/common.sh"
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
    -i, --interactive                  Run in interactive mode (prompts for all values)
    -h, --help                         Show this help message

EXAMPLES:
    # Interactive mode (prompts for all values)
    $0 -i

    # Provide all values as arguments
    $0 --duckdns-token "abc123" \\
       --email "admin@example.com" \\
       --domain "mydomain.duckdns.org" \\
       --bucket "my-backup-bucket" \\
       --tf-state-bucket "my-project-tfstate" \\
       --billing-account "XXXXXX-XXXXXX-XXXXXX"

    # Provide some values, will prompt for missing ones
    $0 -t "abc123" -e "admin@example.com"

EOF
}

# Parse command line arguments
DUCKDNS_TOKEN=""
EMAIL_ADDRESS=""
DOMAIN_NAME=""
GCS_BUCKET_NAME=""
TF_STATE_BUCKET=""
BACKUP_DIR="/var/www/html"
BILLING_ACCOUNT_ID=""
INTERACTIVE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--duckdns-token)
            DUCKDNS_TOKEN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        -b|--bucket)
            GCS_BUCKET_NAME="$2"
            shift 2
            ;;
        -s|--tf-state-bucket)
            TF_STATE_BUCKET="$2"
            shift 2
            ;;
        -r|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -a|--billing-account)
            BILLING_ACCOUNT_ID="$2"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "${PROJECT_ID}" ]]; then
    log_error "No active GCP project. Run: gcloud config set project PROJECT_ID"
    exit 1
fi

echo "============================================================"
log_info "Creating Secrets in Project: ${PROJECT_ID}"
echo "============================================================"

# Function to create or update a secret
create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local description="$3"

    if [[ -z "${secret_value}" ]]; then
        log_error "Secret value for '${secret_name}' cannot be empty."
        return 1
    fi

    # Check if secret exists
    if gcloud secrets describe "${secret_name}" &>/dev/null; then
        log_warn "Secret '${secret_name}' already exists. Adding new version..."
        echo -n "${secret_value}" | gcloud secrets versions add "${secret_name}" --data-file=-
        log_success "Updated secret: ${secret_name}"
    else
        log_info "Creating secret: ${secret_name}"
        echo -n "${secret_value}" | gcloud secrets create "${secret_name}" \
            --data-file=- \
            --replication-policy="automatic" \
            --labels="managed-by=script"
        log_success "Created secret: ${secret_name}"
    fi
}

# Prompt for missing values or if interactive mode
if [[ "${INTERACTIVE_MODE}" == "true" ]] || [[ -z "${DUCKDNS_TOKEN}" ]]; then
    echo ""
    log_info "Enter DuckDNS Token (or press Enter to skip):"
    read -rsp "DuckDNS Token: " DUCKDNS_TOKEN_INPUT
    echo ""
    [[ -n "${DUCKDNS_TOKEN_INPUT}" ]] && DUCKDNS_TOKEN="${DUCKDNS_TOKEN_INPUT}"
fi

if [[ "${INTERACTIVE_MODE}" == "true" ]] || [[ -z "${EMAIL_ADDRESS}" ]]; then
    read -rp "Email Address: " EMAIL_ADDRESS_INPUT
    [[ -n "${EMAIL_ADDRESS_INPUT}" ]] && EMAIL_ADDRESS="${EMAIL_ADDRESS_INPUT}"
fi

if [[ "${INTERACTIVE_MODE}" == "true" ]] || [[ -z "${DOMAIN_NAME}" ]]; then
    read -rp "Domain Name (e.g., mydomain.duckdns.org): " DOMAIN_NAME_INPUT
    [[ -n "${DOMAIN_NAME_INPUT}" ]] && DOMAIN_NAME="${DOMAIN_NAME_INPUT}"
fi

if [[ "${INTERACTIVE_MODE}" == "true" ]] || [[ -z "${GCS_BUCKET_NAME}" ]]; then
    read -rp "GCS Backup Bucket Name: " GCS_BUCKET_NAME_INPUT
    [[ -n "${GCS_BUCKET_NAME_INPUT}" ]] && GCS_BUCKET_NAME="${GCS_BUCKET_NAME_INPUT}"
fi

if [[ "${INTERACTIVE_MODE}" == "true" ]] || [[ -z "${TF_STATE_BUCKET}" ]]; then
    read -rp "Terraform State Bucket Name (default: ${PROJECT_ID}-tfstate): " TF_STATE_BUCKET_INPUT
    TF_STATE_BUCKET="${TF_STATE_BUCKET_INPUT:-${PROJECT_ID}-tfstate}"
fi

if [[ "${INTERACTIVE_MODE}" == "true" ]]; then
    read -rp "Backup Directory (default: /var/www/html): " BACKUP_DIR_INPUT
    [[ -n "${BACKUP_DIR_INPUT}" ]] && BACKUP_DIR="${BACKUP_DIR_INPUT}"
fi

if [[ "${INTERACTIVE_MODE}" == "true" ]] || [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
    echo ""
    log_info "To find your billing account ID, run: gcloud billing accounts list"
    read -rp "Billing Account ID: " BILLING_ACCOUNT_ID_INPUT
    [[ -n "${BILLING_ACCOUNT_ID_INPUT}" ]] && BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID_INPUT}"
fi

echo ""
echo "============================================================"
log_info "Creating secrets with provided values..."
echo "============================================================"

# Create secrets
[[ -n "${DUCKDNS_TOKEN}" ]] && create_secret "duckdns_token" "${DUCKDNS_TOKEN}" "DuckDNS API token"
[[ -n "${EMAIL_ADDRESS}" ]] && create_secret "email_address" "${EMAIL_ADDRESS}" "Email for SSL notifications"
[[ -n "${DOMAIN_NAME}" ]] && create_secret "domain_name" "${DOMAIN_NAME}" "Domain name"
[[ -n "${GCS_BUCKET_NAME}" ]] && create_secret "gcs_bucket_name" "${GCS_BUCKET_NAME}" "GCS backup bucket"
[[ -n "${TF_STATE_BUCKET}" ]] && create_secret "tf_state_bucket" "${TF_STATE_BUCKET}" "Terraform state bucket"
[[ -n "${BACKUP_DIR}" ]] && create_secret "backup_dir" "${BACKUP_DIR}" "Directory to backup"
[[ -n "${BILLING_ACCOUNT_ID}" ]] && create_secret "billing_account_id" "${BILLING_ACCOUNT_ID}" "GCP billing account ID"

echo ""
echo "============================================================"
log_success "Secrets creation complete!"
echo "============================================================"
log_info "View secrets: gcloud secrets list"
log_info "Read secret: gcloud secrets versions access latest --secret=SECRET_NAME"
echo "============================================================"
# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Default values
DUCKDNS_TOKEN=""
EMAIL_ADDRESS=""
DOMAIN_NAME=""
GCS_BUCKET_NAME=""
TF_STATE_BUCKET=""
BACKUP_DIR="/var/www/html"
BILLING_ACCOUNT_ID=""
INTERACTIVE_MODE=false
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
    -t, --duckdns-token TOKEN          DuckDNS token (or use config.sh)
    -e, --email EMAIL                  Email address for SSL notifications (or use config.sh)
    -d, --domain DOMAIN                Domain name (e.g., mydomain.duckdns.org) (or use config.sh)
    -b, --bucket BUCKET                GCS backup bucket name (or use config.sh)
    -s, --tf-state-bucket BUCKET       Terraform state bucket name (or use config.sh)
    -r, --backup-dir DIR               Directory to backup (default: /var/www/html)
    -a, --billing-account ID           GCP billing account ID (or use config.sh)
    --project-id ID                    GCP project ID (or use config.sh)
    -i, --interactive                  Run in interactive mode (prompts for all values)
    -h, --help                         Show this help message

EXAMPLES:
    # Interactive mode (prompts for all values not in config.sh)
    $0 -i

    # Provide all values as arguments, overriding config.sh
    $0 --duckdns-token "abc123" \\
       --email "admin@example.com"
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
        -i|--interactive)      INTERACTIVE_MODE=true; shift;;
        -h|--help)             show_usage; exit 0;;
        *)                     log_error "Unknown option: $1"; show_usage; exit 1;;
    esac
done

# If PROJECT_ID is not set by args or config, get it from gcloud
if [[ -z "${PROJECT_ID}" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
fi


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

    if [[ -z "${secret_value}" ]]; then
        # This is not an error, just skipping creation
        log_info "Secret value for '${secret_name}' is empty. Skipping."
        return 0
    fi

    # Check if secret exists
    if gcloud secrets describe "${secret_name}" --project="${PROJECT_ID}" &>/dev/null; then
        # Secret exists, check if the latest version matches
        local latest_value
        latest_value=$(gcloud secrets versions access latest --secret="${secret_name}" --project="${PROJECT_ID}")

        if [[ "${latest_value}" == "${secret_value}" ]]; then
            log_info "Secret '${secret_name}' is already up-to-date."
        else
            log_warn "Secret '${secret_name}' exists but has a different value. Adding new version..."
            echo -n "${secret_value}" | gcloud secrets versions add "${secret_name}" --data-file=- --project="${PROJECT_ID}"
            log_success "Updated secret: ${secret_name}"
        fi
    else
        log_info "Creating secret: ${secret_name}"
        echo -n "${secret_value}" | gcloud secrets create "${secret_name}" \
            --data-file=- \
            --replication-policy="automatic" \
            --labels="managed-by=script" \
            --project="${PROJECT_ID}"
        log_success "Created secret: ${secret_name}"
    fi
}

# Prompt for missing values if in interactive mode
if [[ "${INTERACTIVE_MODE}" == "true" ]]; then
    if [[ -z "${DUCKDNS_TOKEN}" ]]; then
        read -rsp "Enter DuckDNS Token: " DUCKDNS_TOKEN_INPUT
        DUCKDNS_TOKEN="${DUCKDNS_TOKEN_INPUT}"
        echo
    fi
    if [[ -z "${EMAIL_ADDRESS}" ]]; then
        read -rp "Enter Email Address: " EMAIL_ADDRESS_INPUT
        EMAIL_ADDRESS="${EMAIL_ADDRESS_INPUT}"
    fi
    if [[ -z "${DOMAIN_NAME}" ]]; then
        read -rp "Enter Domain Name: " DOMAIN_NAME_INPUT
        DOMAIN_NAME="${DOMAIN_NAME_INPUT}"
    fi
    if [[ -z "${GCS_BUCKET_NAME}" ]]; then
        read -rp "Enter GCS Backup Bucket Name: " GCS_BUCKET_NAME_INPUT
        GCS_BUCKET_NAME="${GCS_BUCKET_NAME_INPUT}"
    fi
    if [[ -z "${TF_STATE_BUCKET}" ]]; then
        read -rp "Enter Terraform State Bucket Name (default: ${PROJECT_ID}-tfstate): " TF_STATE_BUCKET_INPUT
        TF_STATE_BUCKET="${TF_STATE_BUCKET_INPUT:-${PROJECT_ID}-tfstate}"
    fi
    if [[ -z "${BACKUP_DIR}" ]]; then
        read -rp "Enter Backup Directory (default: /var/www/html): " BACKUP_DIR_INPUT
        BACKUP_DIR="${BACKUP_DIR_INPUT:-/var/www/html}"
    fi
    if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
        log_info "To find your billing account ID, run: gcloud billing accounts list"
        read -rp "Enter Billing Account ID: " BILLING_ACCOUNT_ID_INPUT
        BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID_INPUT}"
    fi
fi


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
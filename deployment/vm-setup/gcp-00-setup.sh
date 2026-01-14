#!/bin/bash
#
# This script orchestrates the entire GCP setup process.
# It sources the configuration and then runs each setup script in sequence.

set -eo pipefail

# --- Preamble ---

# Absolute path to the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common logging functions
# shellcheck source=deployment/vm-setup/common.sh
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || {
    # Fallback logging functions if common.sh is not available
    log_info() {
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
    }
    log_error() {
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
    }
    log_success() {
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [✅ SUCCESS] $*"
    }
    log_warn() {
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
    }
}

# Legacy function for backward compatibility
log() {
    log_info "$@"
}

declare -A config

# Function to load config from config.sh and prompt for missing values
load_and_prompt_config() {
    local config_file="${SCRIPT_DIR}/config.sh"
    local config_example_file="${SCRIPT_DIR}/config.sh.example"

    if [[ -f "${config_file}" ]]; then
        log "Sourcing configuration from ${config_file}..."
        # shellcheck source=deployment/vm-setup/config.sh.example
        source "${config_file}"
    else
        log "WARNING: Configuration file config.sh not found."
        log "Using default values from config.sh.example and prompting for input."
        # shellcheck source=deployment/vm-setup/config.sh.example
        source "${config_example_file}"
    fi

    local -A config_keys=(
        [PROJECT_ID]="Your GCP project ID"
        [ZONE]="The GCP zone to deploy resources in (e.g., us-west1-a)"
        [VM_NAME]="The name of the VM to create"
        [FIREWALL_RULE_NAME]="The name of the firewall rule to create"
        [TAGS]="The network tags to apply to the VM (e.g., http-server,https-server)"
        [REPO_NAME]="The name of the Artifact Registry repository to create"
        [REPO_LOCATION]="The location of the Artifact Registry repository (e.g., us-central1)"
        [EMAIL_ADDRESS]="The email address for monitoring notifications"
        [DISPLAY_NAME]="The display name for the notification channel (e.g., Admin)"
        [DOMAIN]="The domain name to monitor (e.g., your-domain.com)"
        [DUCKDNS_TOKEN]="Your DuckDNS token (if using DuckDNS)"
        [GCS_BUCKET_NAME]="The name of the GCS bucket for backups"
        [TF_STATE_BUCKET]="The name of the GCS bucket for Terraform state"
        [BACKUP_DIR]="The absolute path of the directory to back up (e.g., /var/www/html)"
        [BILLING_ACCOUNT_ID]="Your GCP billing account ID"
    )

    log "Checking configuration values..."
    for key in "${!config_keys[@]}"; do
        local value_from_env="${!key}"
        if [[ -z "${value_from_env}" ]]; then
            if [[ "$key" == "PROJECT_ID" ]]; then
                value_from_env=$(gcloud config get-value project 2>/dev/null || echo "")
            elif [[ "$key" == "BILLING_ACCOUNT_ID" ]]; then
                value_from_env=$(gcloud billing accounts list --format='value(accountId)' --limit=1 2>/dev/null || echo "")
            fi
        fi

        if [[ -z "${value_from_env}" ]]; then
            read -rp "Enter ${config_keys[${key}]}: " "config[${key}]"
        else
            config[${key}]="${value_from_env}"
            log "  ${config_keys[${key}]}: ${config[${key}]}"
        fi
    done

    # Final check for critical values
    if [[ -z "${config[PROJECT_ID]}" || -z "${config[ZONE]}" || -z "${config[EMAIL_ADDRESS]}" || -z "${config[DOMAIN]}" ]]; then
        log_error "Critical configuration values (PROJECT_ID, ZONE, EMAIL_ADDRESS, DOMAIN) are missing."
        exit 1
    fi
}

# Function to verify gcloud authentication
verify_gcloud_auth() {
    log "Verifying gcloud authentication..."
    
    # Check if any account is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
        log_error "No active gcloud account found."
        log_error ""
        log_error "Please authenticate with gcloud:"
        log_error "  $ gcloud auth login"
        log_error ""
        log_error "Or if you have multiple accounts, set the active one:"
        log_error "  $ gcloud config set account YOUR_EMAIL@example.com"
        log_error ""
        log_error "Available accounts:"
        gcloud auth list 2>/dev/null || echo "  (none configured)"
        exit 1
    fi
    
    # Verify project is set
    if ! gcloud config get-value project &>/dev/null; then
        log_error "No GCP project is configured."
        log_error ""
        log_error "Please set your project:"
        log_error "  $ gcloud config set project PROJECT_ID"
        log_error ""
        log_error "Or list available projects:"
        log_error "  $ gcloud projects list"
        exit 1
    fi
    
    log "✓ gcloud authentication verified"
}

# --- Main ---

echo ""
printf '=%.0s' {1..60}; echo
log "Starting GCP setup..."
log "⏱️  Estimated time: 2-3 minutes"
printf '=%.0s' {1..60}; echo
echo ""

# Verify required tools
for tool in gcloud jq; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "Required tool '$tool' is not installed."
        exit 1
    fi
done

# Verify gcloud authentication before proceeding
verify_gcloud_auth

START_TIME=$(date +%s)
load_and_prompt_config

# Ensure scripts are executable
chmod +x "${SCRIPT_DIR}"/gcp-0[1-6]*.sh

log "Checking existing resources..."
SKIP_COUNT=0
CREATE_COUNT=0

echo ""
# Check VM
if gcloud compute instances describe "${config[VM_NAME]}" --zone="${config[ZONE]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log "  ⏭️  VM '${config[VM_NAME]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log "  ✨ VM '${config[VM_NAME]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

# Check Firewall
if gcloud compute firewall-rules describe "${config[FIREWALL_RULE_NAME]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log "  ⏭️  Firewall rule '${config[FIREWALL_RULE_NAME]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log "  ✨ Firewall rule '${config[FIREWALL_RULE_NAME]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

# Check Artifact Registry
if gcloud artifacts repositories describe "${config[REPO_NAME]}" --location="${config[REPO_LOCATION]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log "  ⏭️  Artifact Registry '${config[REPO_NAME]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log "  ✨ Artifact Registry '${config[REPO_NAME]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

echo ""
log "📊 Summary: $CREATE_COUNT to create, $SKIP_COUNT to skip"
echo ""
read -p "Continue with setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log "Setup cancelled."
  exit 0
fi

echo ""
printf '=%.0s' {1..60}; echo
log "🚀 Starting setup execution..."
printf '=%.0s' {1..60}; echo

# Execute setup scripts in order with correct filenames
log "Step 1/5: Creating VM..."
"${SCRIPT_DIR}/gcp-01-create-vm.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[PROJECT_ID]}"

log "Step 2/5: Opening firewall..."
"${SCRIPT_DIR}/gcp-02-firewall-open.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[FIREWALL_RULE_NAME]}" "${config[PROJECT_ID]}" "${config[TAGS]}"

log "Step 3/5: Setting up monitoring..."
"${SCRIPT_DIR}/gcp-03-setup-monitoring.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[EMAIL_ADDRESS]}" "${config[DISPLAY_NAME]}" "${config[DOMAIN]}" "${config[PROJECT_ID]}"

log "Step 4/5: Creating secrets..."
"${SCRIPT_DIR}/gcp-04-create-secrets.sh" \
  --project-id "${config[PROJECT_ID]}" \
  --duckdns-token "${config[DUCKDNS_TOKEN]}" \
  --email "${config[EMAIL_ADDRESS]}" \
  --domain "${config[DOMAIN]}" \
  --bucket "${config[GCS_BUCKET_NAME]}" \
  --tf-state-bucket "${config[TF_STATE_BUCKET]}" \
  --backup-dir "${config[BACKUP_DIR]}" \
  --billing-account "${config[BILLING_ACCOUNT_ID]}"

log "Step 5/5: Creating artifact registry..."
"${SCRIPT_DIR}/gcp-05-create-artifact-registry.sh" "${config[REPO_NAME]}" "${config[REPO_LOCATION]}" "${config[PROJECT_ID]}"

echo ""
printf '=%.0s' {1..60}; echo
log "✅ GCP setup completed successfully!"
printf '=%.0s' {1..60}; echo

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo ""
log "⏱️  Total setup time: $((DURATION / 60))m $((DURATION % 60))s"
echo ""
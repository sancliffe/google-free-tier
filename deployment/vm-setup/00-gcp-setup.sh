#!/bin/bash
#
# This script orchestrates the entire GCP setup process.
# It sources the configuration and then runs each setup script in sequence.

set -eo pipefail

# --- Preamble ---

# Absolute path to the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Functions ---

# Function to log messages.
log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Function to log errors.
log_error() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $*" >&2
}

declare -A config

# Function to load config from config.sh and prompt for missing values
load_and_prompt_config() {
    local config_file="${SCRIPT_DIR}/config.sh"
    local config_example_file="${SCRIPT_DIR}/config.sh.example"

    if [[ -f "${config_file}" ]]; then
        log "Sourcing configuration from ${config_file}..."
        source "${config_file}"
    else
        log "WARNING: Configuration file config.sh not found."
        log "Using default values from config.sh.example and prompting for input."
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

# --- Main ---

log "Starting GCP setup..."
log "⏱️  Estimated time: 2-3 minutes"

# Verify required tools
for tool in gcloud jq; do
    if ! command -v $tool &> /dev/null; then
        log_error "Required tool '$tool' is not installed."
        exit 1
    fi
done

START_TIME=$(date +%s)
load_and_prompt_config

# Ensure scripts are executable
chmod +x "${SCRIPT_DIR}"/0[1-5]-gcp-*.sh

log "Checking existing resources..."
SKIP_COUNT=0
CREATE_COUNT=0

# Check VM
if gcloud compute instances describe "${config[VM_NAME]}" --zone="${config[ZONE]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log "  VM '${config[VM_NAME]}': Already exists ⏭️"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log "  VM '${config[VM_NAME]}': Will create ✨"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

# Check Firewall
if gcloud compute firewall-rules describe "${config[FIREWALL_RULE_NAME]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log "  Firewall rule '${config[FIREWALL_RULE_NAME]}': Already exists ⏭️"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log "  Firewall rule '${config[FIREWALL_RULE_NAME]}': Will create ✨"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

# Check Artifact Registry
if gcloud artifacts repositories describe "${config[REPO_NAME]}" --location="${config[REPO_LOCATION]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log "  Artifact Registry '${config[REPO_NAME]}': Already exists ⏭️"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log "  Artifact Registry '${config[REPO_NAME]}': Will create ✨"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

log "Summary: $CREATE_COUNT to create, $SKIP_COUNT to skip"
read -p "Continue with setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log "Setup cancelled."
  exit 0
fi

# Execute setup scripts in order with corrected filenames
log "Step 1: Creating VM..."
"${SCRIPT_DIR}/01-gcp-create-vm.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[PROJECT_ID]}"

log "Step 2: Opening firewall..."
"${SCRIPT_DIR}/02-gcp-firewall-open.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[FIREWALL_RULE_NAME]}" "${config[PROJECT_ID]}" "${config[TAGS]}"

log "Step 3: Setting up monitoring..."
"${SCRIPT_DIR}/03-gcp-setup-monitoring.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[EMAIL_ADDRESS]}" "${config[DISPLAY_NAME]}" "${config[DOMAIN]}" "${config[PROJECT_ID]}"

log "Step 4: Creating secrets..."
"${SCRIPT_DIR}/04-gcp-create-secrets.sh" \
  --project-id "${config[PROJECT_ID]}" \
  --duckdns-token "${config[DUCKDNS_TOKEN]}" \
  --email "${config[EMAIL_ADDRESS]}" \
  --domain "${config[DOMAIN]}" \
  --bucket "${config[GCS_BUCKET_NAME]}" \
  --tf-state-bucket "${config[TF_STATE_BUCKET]}" \
  --backup-dir "${config[BACKUP_DIR]}" \
  --billing-account "${config[BILLING_ACCOUNT_ID]}"

log "Step 5: Creating artifact registry..."
"${SCRIPT_DIR}/05-gcp-create-artifact-registry.sh" "${config[REPO_NAME]}" "${config[REPO_LOCATION]}" "${config[PROJECT_ID]}"

log "GCP setup completed successfully!"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "⏱️  Setup completed in $((DURATION / 60))m $((DURATION % 60))s"
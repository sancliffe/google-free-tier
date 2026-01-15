#!/bin/bash
#
# This script orchestrates the entire GCP setup process.
# It sources the configuration and then runs each setup script in sequence.

set -eo pipefail

# --- Preamble ---

# Absolute path to the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common logging functions
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || {
    # Fallback logging functions if common.sh is not available
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    NC='\033[0m'
    
    log_info() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${CYAN}[INFO]${NC} $*"
    }
    log_error() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${RED}[ERROR]${NC} $*" >&2
    }
    log_success() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${GREEN}[✅ SUCCESS]${NC} $*"
    }
    log_warn() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${YELLOW}[WARN]${NC} $*"
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
        # shellcheck source=/dev/null
        source "${config_file}"
    else
        log "WARNING: Configuration file config.sh not found."
        log "Using default values from config.sh.example and prompting for input."
        # shellcheck source=/dev/null
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
            log_info "  ${config_keys[${key}]}: ${config[${key}]}"
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
    log_info "Verifying gcloud authentication..."
    
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
    
    log_success "✓ gcloud authentication verified"
}

# Associative array to track which resources have been successfully created
declare -A CREATED_STATUS=(
    [VM]=false
    [FIREWALL]=false
    [MONITORING]=false
    [GCS_BACKUP_BUCKET]=false
    [GCS_TF_BUCKET]=false
    [SECRETS]=false
    [ARTIFACT_REGISTRY]=false
)

# Function to run a command with retries and error handling
# Arguments:
#   $1: The command string to execute
#   $2: A description of the command for logging
#   $3: (Optional) Number of retries (default: 5)
#   $4: (Optional) Delay between retries in seconds (default: 10)
run_command_with_retry() {
    local cmd="$1"
    local description="$2"
    local retries="${3:-5}"   # Default to 5 retries
    local delay="${4:-10}"   # Default to 10 seconds delay
    local attempt=1
    local success=0

    log_info "Starting: $description"

    while [[ $attempt -le $retries ]]; do
        log_info "  Attempt $attempt/$retries: Executing '$cmd'"
        set +e # Temporarily disable 'e' to allow command failure without exiting script
        eval "$cmd"
        local exit_code=$?
        set -e # Re-enable 'e'

        if [[ $exit_code -eq 0 ]]; then
            log_success "  $description succeeded on attempt $attempt."
            success=1
            break
        else
        log_warn "  $description failed on attempt $attempt (exit code: $exit_code). Retrying in $delay seconds..."

            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    if [[ $success -eq 0 ]]; then
        log_error "  $description failed after $retries attempts. Exiting."
        cleanup_on_failure
        exit 1 # Ensure the script exits after cleanup
    fi
    return 0
}

# Function to cleanup resources in case of failure
cleanup_resources() {
    log_info "Cleaning up resources..."
    
    # Execute the cleanup script with necessary parameters
    "${SCRIPT_DIR}/gcp-cleanup.sh" \
        --vm-name "${config[VM_NAME]}" \
        --zone "${config[ZONE]}" \
        --firewall-rule-name "${config[FIREWALL_RULE_NAME]}" \
        --repo-name "${config[REPO_NAME]}" \
        --repo-location "${config[REPO_LOCATION]}" \
        --project-id "${config[PROJECT_ID]}"

    log_info "Resource cleanup completed."

    exit 1
}

# --- Main ---

echo ""
printf '=%.0s' {1..60}; echo
log "Starting GCP setup..."
log_info "⏱️  Estimated time: 2-3 minutes"
printf '=%.0s' {1..60}; echo
echo ""

# Verify required tools (already done in common.sh or fallback)
for tool in gcloud jq gsutil; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "Required tool '$tool' is not installed."
        exit 1
    fi
done

# Verify gcloud authentication before proceeding
verify_gcloud_auth

START_TIME=$(date +%s)
load_and_prompt_config

# Ensure all setup scripts are executable
chmod +x "${SCRIPT_DIR}"/gcp-0*.sh

log "Checking existing resources..."
SKIP_COUNT=0
CREATE_COUNT=0

echo ""
# Check VM 
if gcloud compute instances describe "${config[VM_NAME]}" --zone="${config[ZONE]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log_info "  ⏭️  VM '${config[VM_NAME]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log_info "  ✨ VM '${config[VM_NAME]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi 

# Check Firewall  
if gcloud compute firewall-rules describe "${config[FIREWALL_RULE_NAME]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log_info "  ⏭️  Firewall rule '${config[FIREWALL_RULE_NAME]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log_info "  ✨ Firewall rule '${config[FIREWALL_RULE_NAME]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi 

# Check GCS Backup Bucket (NEW check)
if gsutil ls "gs://${config[GCS_BUCKET_NAME]}" &>/dev/null; then
  log_info "  ⏭️  GCS Backup Bucket '${config[GCS_BUCKET_NAME]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log_info "  ✨ GCS Backup Bucket '${config[GCS_BUCKET_NAME]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

# Check GCS Terraform State Bucket (NEW check)
if gsutil ls "gs://${config[TF_STATE_BUCKET]}" &>/dev/null; then
  log_info "  ⏭️  GCS Terraform State Bucket '${config[TF_STATE_BUCKET]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log_info "  ✨ GCS Terraform State Bucket '${config[TF_STATE_BUCKET]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

# Check Artifact Registry  
if gcloud artifacts repositories describe "${config[REPO_NAME]}" --location="${config[REPO_LOCATION]}" --project="${config[PROJECT_ID]}" &>/dev/null; then
  log_info "  ⏭️  Artifact Registry '${config[REPO_NAME]}': Already exists"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log_info "  ✨ Artifact Registry '${config[REPO_NAME]}': Will create"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi 

echo ""
log "📊 Summary: $CREATE_COUNT to create, $SKIP_COUNT to skip"
echo ""
read -p "Continue with setup? (y/N): " -n 1 -r
echo # Add a newline after the prompt
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_info "Setup cancelled."
  exit 0
fi

echo ""
printf '=%.0s' {1..60}; echo
log_info "🚀 Starting setup execution..."
printf '=%.0s' {1..60}; echo

# Execute setup scripts in order with correct filenames
run_command_with_retry \
    "\"${SCRIPT_DIR}/gcp-01-create-vm.sh\" \"${config[VM_NAME]}\" \"${config[ZONE]}\" \"${config[PROJECT_ID]}\"" \
    "Step 1/8: Creating VM '${config[VM_NAME]}'"
CREATED_STATUS[VM]=true

run_command_with_retry \
    "\"${SCRIPT_DIR}/gcp-02-firewall-open.sh\" \"${config[VM_NAME]}\" \"${config[ZONE]}\" \"${config[FIREWALL_RULE_NAME]}\" \"${config[PROJECT_ID]}\" \"${config[TAGS]}\"" \
    "Step 2/8: Opening firewall rule '${config[FIREWALL_RULE_NAME]}'"
CREATED_STATUS[FIREWALL]=true

run_command_with_retry \
    "\"${SCRIPT_DIR}/gcp-03-setup-monitoring.sh\" \"${config[VM_NAME]}\" \"${config[ZONE]}\" \"${config[EMAIL_ADDRESS]}\" \"${config[DISPLAY_NAME]}\" \"${config[DOMAIN]}\" \"${config[PROJECT_ID]}\"" \
    "Step 3/8: Setting up monitoring"
CREATED_STATUS[MONITORING]=true

# NEW STEP: Create GCS Buckets
log_info "Step 4/8: Creating GCS buckets..."
if ! gsutil ls "gs://${config[GCS_BUCKET_NAME]}" &>/dev/null; then
  run_command_with_retry \
      "gsutil mb -p \"${config[PROJECT_ID]}\" \"gs://${config[GCS_BUCKET_NAME]}\"" \
      "Creating GCS Backup Bucket '${config[GCS_BUCKET_NAME]}'"
  CREATED_STATUS[GCS_BACKUP_BUCKET]=true
else
  log_info "  GCS Backup Bucket '${config[GCS_BUCKET_NAME]}' already exists, skipping creation."
fi

if ! gsutil ls "gs://${config[TF_STATE_BUCKET]}" &>/dev/null; then
  run_command_with_retry \
      "gsutil mb -p \"${config[PROJECT_ID]}\" \"gs://${config[TF_STATE_BUCKET]}\"" \
      "Creating GCS Terraform State Bucket '${config[TF_STATE_BUCKET]}'"
  CREATED_STATUS[GCS_TF_BUCKET]=true
else
  log_info "  GCS Terraform State Bucket '${config[TF_STATE_BUCKET]}' already exists, skipping creation."
fi

run_command_with_retry \
    "\"${SCRIPT_DIR}/gcp-04-create-secrets.sh\" --project-id \"${config[PROJECT_ID]}\" --duckdns-token \"${config[DUCKDNS_TOKEN]}\" --email \"${config[EMAIL_ADDRESS]}\" --domain \"${config[DOMAIN]}\" --bucket \"${config[GCS_BUCKET_NAME]}\" --tf-state-bucket \"${config[TF_STATE_BUCKET]}\" --backup-dir \"${config[BACKUP_DIR]}\" --billing-account \"${config[BILLING_ACCOUNT_ID]}\"" \
    "Step 5/8: Creating secrets"
CREATED_STATUS[SECRETS]=true

run_command_with_retry \
    "\"${SCRIPT_DIR}/gcp-05-create-artifact-registry.sh\" \"${config[REPO_NAME]}\" \"${config[REPO_LOCATION]}\" \"${config[PROJECT_ID]}\"" \
    "Step 6/8: Creating artifact registry '${config[REPO_NAME]}'"
CREATED_STATUS[ARTIFACT_REGISTRY]=true

run_command_with_retry \
    "\"${SCRIPT_DIR}/gcp-06-validate.sh\"" \
    "Step 7/8: Validating GCP setup"

log_info "Step 8/8: Configuring VM environment and SSHing..."

# Define variables to export to the VM's environment
# These are variables that the VM itself might need for subsequent operations or scripts.
declare -a VM_ENV_VARS=(
  "PROJECT_ID=${config[PROJECT_ID]}"
  "ZONE=${config[ZONE]}"
  "VM_NAME=${config[VM_NAME]}"
  "EMAIL_ADDRESS=${config[EMAIL_ADDRESS]}"
  "DOMAIN=${config[DOMAIN]}"
  "DUCKDNS_TOKEN=${config[DUCKDNS_TOKEN]}" # Note: Storing sensitive info in .bashrc might not be ideal for production. Consider Secret Manager access on VM.
  "GCS_BUCKET_NAME=${config[GCS_BUCKET_NAME]}"
  "BACKUP_DIR=${config[BACKUP_DIR]}"
)

# Construct the command to set environment variables persistently on the VM
ENV_SETUP_COMMAND=""
for var_entry in "${VM_ENV_VARS[@]}"; do
  KEY="${var_entry%%=*}"
  VALUE="${var_entry#*=}"
  # Escape double quotes in the value to ensure it's correctly interpreted by bash on the VM
  ESCAPED_VALUE=$(printf %s "$VALUE" | sed 's/"/\\"/g')
  ENV_SETUP_COMMAND+="echo 'export $KEY=\"$ESCAPED_VALUE\"' >> ~/.bashrc;"
done
ENV_SETUP_COMMAND+="echo 'Environment variables set in ~/.bashrc. Please source ~/.bashrc or re-login for them to take effect in new sessions.'"

# Execute the command on the VM to set environment variables
run_command_with_retry \
    "gcloud compute ssh \"${config[VM_NAME]}\" --zone=\"${config[ZONE]}\" --project=\"${config[PROJECT_ID]}\" --command \"$ENV_SETUP_COMMAND\"" \
    "Setting environment variables on VM '${config[VM_NAME]}' in ~/.bashrc"

# SSH into the VM
log_info "Initiating SSH session to VM '${config[VM_NAME]}'..."
# This is an interactive command, so we don't wrap it in run_command_with_retry
# as it's the final interactive step.
gcloud compute ssh "${config[VM_NAME]}" --zone="${config[ZONE]}" --project="${config[PROJECT_ID]}"

echo ""
printf '=%.0s' {1..60}; echo
log_success "✅ GCP setup completed successfully!"
printf '=%.0s' {1..60}; echo

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log_info "⏱️  Total setup time: $((DURATION / 60))m $((DURATION % 60))s"
echo ""
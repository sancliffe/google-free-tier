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

declare -A config

# Function to load config from config.sh and prompt for missing values
load_and_prompt_config() {
    local config_file="${SCRIPT_DIR}/config.sh"
    local config_example_file="${SCRIPT_DIR}/config.sh.example"

    if [[ -f "${config_file}" ]]; then
        log "Sourcing configuration from ${config_file}..."
        # Source config.sh to get initial values into environment variables
        source "${config_file}"
    else
        log "WARNING: Configuration file config.sh not found."
        log "Using default values from config.sh.example and prompting for input."
        # Source config.sh.example to get initial values into environment variables
        source "${config_example_file}"
    fi

    # Define all expected config keys and their descriptions for prompting
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
            # Special handling for PROJECT_ID and BILLING_ACCOUNT_ID to try gcloud
            if [[ "$key" == "PROJECT_ID" ]]; then
                value_from_env=$(gcloud config get-value project 2>/dev/null || echo "")
            elif [[ "$key" == "BILLING_ACCOUNT_ID" ]]; then
                value_from_env=$(gcloud billing accounts list --format='value(accountId)' --limit=1 2>/dev/null || echo "")
            fi
        fi

        if [[ -z "${value_from_env}" ]]; then
            read -rp "Enter ${config_keys[${key}]}: " "config[${key}]"
            # If user enters nothing, still assign empty
            if [[ -z "${config[${key}]}" ]]; then
                log "WARNING: ${config_keys[${key}]} was left empty. This may cause issues."
            fi
        else
            config[${key}]="${value_from_env}"
            log "  ${config_keys[${key}]}: ${config[${key}]}"
        fi
    done

    # Final check for critical values
    if [[ -z "${config[PROJECT_ID]}" || -z "${config[ZONE]}" || -z "${config[EMAIL_ADDRESS]}" || -z "${config[DOMAIN]}" ]]; then
        log_error "ERROR: Critical configuration values (PROJECT_ID, ZONE, EMAIL_ADDRESS, DOMAIN) are missing."
        log_error "Please ensure these are set in config.sh or provided interactively."
        exit 1
    fi

    log "Configuration loaded."
}

# --- Main ---


  log "Starting GCP setup..."
  log "⏱️  Estimated time: 2-3 minutes"
  log ""

  # Record start time
  START_TIME=$(date +%s)

  load_and_prompt_config
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

  

    log ""

    log "Summary: $CREATE_COUNT to create, $SKIP_COUNT to skip"

    log ""

    read -p "Continue with setup? (y/N): " -n 1 -r

    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then

      log "Setup cancelled."

      exit 0

    fi

  

    # Execute setup scripts in order.

    log "Step 1: Creating VM..."

    "${SCRIPT_DIR}/1-create-vm.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[PROJECT_ID]}"

  

      log "Step 2: Opening firewall..."

  

      "${SCRIPT_DIR}/2-firewall-gcp-open.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[FIREWALL_RULE_NAME]}" "${config[PROJECT_ID]}" "${config[TAGS]}"

  

    log "Step 3: Setting up monitoring..."

    "${SCRIPT_DIR}/3-setup-monitoring.sh" "${config[VM_NAME]}" "${config[ZONE]}" "${config[EMAIL_ADDRESS]}" "${config[DISPLAY_NAME]}" "${config[DOMAIN]}" "${config[PROJECT_ID]}"

  

    log "Step 4: Creating secrets..."

    "${SCRIPT_DIR}/4-create-secrets.sh" \

      --project-id "${config[PROJECT_ID]}" \

      --duckdns-token "${config[DUCKDNS_TOKEN]}" \

      --email "${config[EMAIL_ADDRESS]}" \

      --domain "${config[DOMAIN]}" \

      --bucket "${config[GCS_BUCKET_NAME]}" \

      --tf-state-bucket "${config[TF_STATE_BUCKET]}" \

      --backup-dir "${config[BACKUP_DIR]}" \

      --billing-account "${config[BILLING_ACCOUNT_ID]}"

  

    log "Step 5: Creating artifact registry..."

    "${SCRIPT_DIR}/5-create-artifact-registry.sh" "${config[REPO_NAME]}" "${config[REPO_LOCATION]}" "${config[PROJECT_ID]}"

  

    log "GCP setup completed successfully!"

  

    echo ""

    echo "╔════════════════════════════════════════════════════════════╗"

    echo "║           GCP SETUP SUMMARY                                ║"

    echo "╚════════════════════════════════════════════════════════════╝"

    echo ""

    log "📦 Resources Created:"

    log "  • VM Instance: ${config[VM_NAME]} (zone: ${config[ZONE]})"

    log "  • External IP: $(gcloud compute instances describe "${config[VM_NAME]}" --zone="${config[ZONE]}" --project="${config[PROJECT_ID]}" --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo 'Pending...')"

    log "  • Firewall Rule: ${config[FIREWALL_RULE_NAME]}"

    log "  • Artifact Registry: ${config[REPO_NAME]} (${config[REPO_LOCATION]})"

    log "  • Secrets: $(gcloud secrets list --project="${config[PROJECT_ID]}" --format='value(name)' | wc -l) total"

    echo ""

    log "🔗 Useful Links:"

    log "  • GCP Console: https://console.cloud.google.com/compute/instances?project=${config[PROJECT_ID]}"

    log "  • Artifact Registry: https://console.cloud.google.com/artifacts?project=${config[PROJECT_ID]}"

    log "  • Secret Manager: https://console.cloud.google.com/security/secret-manager?project=${config[PROJECT_ID]}"

    log "  • Monitoring: https://console.cloud.google.com/monitoring?project=${config[PROJECT_ID]}"

    echo ""

    log "📋 Next Steps:"

    log "  1. SSH into VM: gcloud compute ssh ${config[VM_NAME]} --zone=${config[ZONE]} --project=${config[PROJECT_ID]}"

    log "  2. Run host setup scripts (Phase 2)"

    log "  3. Configure DuckDNS and SSL certificates"

    echo ""

    log "💡 Troubleshooting:"

    log "  • View setup logs: Check output above"

    log "  • VM serial console: gcloud compute instances get-serial-port-output ${config[VM_NAME]} --zone=${config[ZONE]} --project=${config[PROJECT_ID]}"

    log "  • Check firewall: gcloud compute firewall-rules list --project=${config[PROJECT_ID]}"

    echo ""

  

    log "Running post-setup validation..."

  

    # Validate VM

    if gcloud compute instances describe "${config[VM_NAME]}" --zone="${config[ZONE]}" --project="${config[PROJECT_ID]}" >/dev/null; then

      log "✓ VM '${config[VM_NAME]}' is accessible"

    else

      log "✗ WARNING: VM '${config[VM_NAME]}' cannot be verified"

    fi

  

    # Validate Artifact Registry

    if gcloud artifacts repositories describe "${config[REPO_NAME]}" --location="${config[REPO_LOCATION]}" --project="${config[PROJECT_ID]}" >/dev/null; then

      log "✓ Artifact Registry '${config[REPO_NAME]}' is accessible"

    else

      log "✗ WARNING: Artifact Registry '${config[REPO_NAME]}' cannot be verified"

    fi

  

    # Check secrets

    SECRET_COUNT=$(gcloud secrets list --project="${config[PROJECT_ID]}" --format="value(name)" | wc -l)

    log "✓ Found $SECRET_COUNT secrets in Secret Manager"

  

    log "Validation complete!"

  

  

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINUTES=$((DURATION / 60))
  SECONDS=$((DURATION % 60))

  log ""
  log "⏱️  Setup completed in ${MINUTES}m ${SECONDS}s"



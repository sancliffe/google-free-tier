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

# --- Main ---

main() {
  log "Starting GCP setup..."
  log "⏱️  Estimated time: 2-3 minutes"
  log ""

  # Record start time
  START_TIME=$(date +%s)

  # Source configuration file.
  if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    # shellcheck source=1-gcp-setup/config.sh
    source "${SCRIPT_DIR}/config.sh"
    log "Sourced configuration from config.sh"
  else
    log "ERROR: Configuration file config.sh not found."
    log "Please copy config.sh.example to config.sh and fill in the required values."
    exit 1
  fi

  log "Checking existing resources..."
  SKIP_COUNT=0
  CREATE_COUNT=0

  # Check VM
  if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
    log "  VM '$VM_NAME': Already exists ⏭️"
    SKIP_COUNT=$((SKIP_COUNT + 1))
  else
    log "  VM '$VM_NAME': Will create ✨"
    CREATE_COUNT=$((CREATE_COUNT + 1))
  fi

  # Check Firewall
  if gcloud compute firewall-rules describe "$FIREWALL_RULE_NAME" --project="$PROJECT_ID" &>/dev/null; then
    log "  Firewall rule: Already exists ⏭️"
    SKIP_COUNT=$((SKIP_COUNT + 1))
  else
    log "  Firewall rule: Will create ✨"
    CREATE_COUNT=$((CREATE_COUNT + 1))
  fi

  # Check Artifact Registry
  if gcloud artifacts repositories describe "$REPO_NAME" --location="$REPO_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
    log "  Artifact Registry: Already exists ⏭️"
    SKIP_COUNT=$((SKIP_COUNT + 1))
  else
    log "  Artifact Registry: Will create ✨"
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
  "${SCRIPT_DIR}/1-create-vm.sh"

  log "Step 2: Opening firewall..."
  "${SCRIPT_DIR}/2-open-firewall.sh"

  log "Step 3: Setting up monitoring..."
  "${SCRIPT_DIR}/3-setup-monitoring.sh"

  log "Step 4: Creating secrets..."
  "${SCRIPT_DIR}/4-create-secrets.sh"

  log "Step 5: Creating artifact registry..."
  "${SCRIPT_DIR}/5-create-artifact-registry.sh"

  log "GCP setup completed successfully!"

  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║           GCP SETUP SUMMARY                                ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  log "📦 Resources Created:"
  log "  • VM Instance: $VM_NAME (zone: $ZONE)"
  log "  • External IP: $(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo 'Pending...')"
  log "  • Firewall Rule: $FIREWALL_RULE_NAME"
  log "  • Artifact Registry: $REPO_NAME (${REPO_LOCATION})"
  log "  • Secrets: $(gcloud secrets list --project="$PROJECT_ID" --format='value(name)' | wc -l) total"
  echo ""
  log "🔗 Useful Links:"
  log "  • GCP Console: https://console.cloud.google.com/compute/instances?project=${PROJECT_ID}"
  log "  • Artifact Registry: https://console.cloud.google.com/artifacts?project=${PROJECT_ID}"
  log "  • Secret Manager: https://console.cloud.google.com/security/secret-manager?project=${PROJECT_ID}"
  log "  • Monitoring: https://console.cloud.google.com/monitoring?project=${PROJECT_ID}"
  echo ""
  log "📋 Next Steps:"
  log "  1. SSH into VM: gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID"
  log "  2. Run host setup scripts (Phase 2)"
  log "  3. Configure DuckDNS and SSL certificates"
  echo ""
  log "💡 Troubleshooting:"
  log "  • View setup logs: Check output above"
  log "  • VM serial console: gcloud compute instances get-serial-port-output $VM_NAME --zone=$ZONE --project=$PROJECT_ID"
  log "  • Check firewall: gcloud compute firewall-rules list --project=$PROJECT_ID"
  echo ""

  log "Running post-setup validation..."

  # Validate VM
  if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null; then
    log "✓ VM '$VM_NAME' is accessible"
  else
    log "✗ WARNING: VM '$VM_NAME' cannot be verified"
  fi

  # Validate Artifact Registry
  if gcloud artifacts repositories describe "$REPO_NAME" --location="$REPO_LOCATION" --project="$PROJECT_ID" >/dev/null; then
    log "✓ Artifact Registry '$REPO_NAME' is accessible"
  else
    log "✗ WARNING: Artifact Registry '$REPO_NAME' cannot be verified"
  fi

  # Check secrets
  SECRET_COUNT=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)" | wc -l)
  log "✓ Found $SECRET_COUNT secrets in Secret Manager"

  log "Validation complete!"

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINUTES=$((DURATION / 60))
  SECONDS=$((DURATION % 60))

  log ""
  log "⏱️  Setup completed in ${MINUTES}m ${SECONDS}s"
}

main "$@"

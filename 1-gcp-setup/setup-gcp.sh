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
}

main "$@"

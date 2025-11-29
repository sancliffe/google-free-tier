#!/bin/bash
#
# This startup script is executed when the VM boots up.
set -e

# --- Logging Setup ---
# Redirect stdout and stderr to a log file and the serial console
exec > >(tee /var/log/startup-script.log | logger -t startup-script -s 2>/dev/console) 2>&1

# --- Run Once Logic ---
GLOBAL_SETUP_MARKER="/var/lib/google-free-tier-setup-complete"
if [ -f "$GLOBAL_SETUP_MARKER" ]; then
    echo "Overall setup already complete. Skipping."
    exit 0
fi

echo "--- Startup Script Initiated ---"

# 1. Fetch secrets from Secret Manager
SECRETS_MARKER="/var/lib/google-free-tier-secrets-fetched"
if [ ! -f "$SECRETS_MARKER" ]; then
    echo "Fetching secrets..."
    export DUCKDNS_TOKEN=$(gcloud secrets versions access latest --secret="duckdns_token" --format="value(payload.data)" | base64 --decode)
    export EMAIL=$(gcloud secrets versions access latest --secret="email_address" --format="value(payload.data)" | base64 --decode)
    export DOMAIN=$(gcloud secrets versions access latest --secret="domain_name" --format="value(payload.data)" | base64 --decode)
    # GCS Bucket Name is now injected via Terraform template
    export GCS_BUCKET_NAME="${gcs_bucket_name}"
    export BACKUP_DIR=$(gcloud secrets versions access latest --secret="backup_dir" --format="value(payload.data)" | base64 --decode)
    touch "$SECRETS_MARKER"
else
    echo "Secrets already fetched. Skipping."
fi


# 2. Download setup scripts from GCS
DOWNLOAD_MARKER="/var/lib/google-free-tier-scripts-downloaded"
if [ ! -f "$DOWNLOAD_MARKER" ]; then
    echo "Downloading setup scripts from gs://${GCS_BUCKET_NAME}/setup-scripts/..."
    mkdir -p /tmp/2-host-setup

    # Download with exponential backoff
    MAX_RETRIES=5
    for ((i=1; i<=MAX_RETRIES; i++)); do
      if gsutil -m cp -r "gs://${GCS_BUCKET_NAME}/setup-scripts/*" /tmp/2-host-setup/; then
        echo "Download successful."
        # Verify files actually exist
        if [ -n "$(ls -A /tmp/2-host-setup 2>/dev/null)" ]; then
          break
        fi
      fi
      if [ $i -eq $MAX_RETRIES ]; then
        echo "CRITICAL ERROR: Failed to download setup scripts after $MAX_RETRIES attempts."
        exit 1
      fi
      BACKOFF=$((2 ** i))
      echo "Download failed (Attempt $i/$MAX_RETRIES). Retrying in ${BACKOFF}s..."
      sleep $BACKOFF
    done

    chmod +x /tmp/2-host-setup/*.sh
    touch "$DOWNLOAD_MARKER"
else
    echo "Setup scripts already downloaded. Skipping."
fi


# 3. Run setup scripts
echo "Running setup scripts..."
(
  set -e # Exit on any error

  SCRIPT_NAMES=(
    "1-create-swap.sh"
    "2-install-nginx.sh"
    "3-setup-duckdns.sh"
    "4-setup-ssl.sh"
    "5-adjust-firewall.sh"
    "6-setup-backups.sh"
    "7-setup-security.sh"
    "8-setup-ops-agent.sh"
  )

  for SCRIPT in "${SCRIPT_NAMES[@]}"; do
    SCRIPT_MARKER="/var/lib/google-free-tier-${SCRIPT}-complete"
    if [ ! -f "$SCRIPT_MARKER" ]; then
        echo "Running /tmp/2-host-setup/$SCRIPT"
        case "$SCRIPT" in
            "3-setup-duckdns.sh"|"4-setup-ssl.sh"|"6-setup-backups.sh")
                sudo -E "/tmp/2-host-setup/$SCRIPT" || exit 1 # Keep environment for secrets
                ;;
            *)
                sudo "/tmp/2-host-setup/$SCRIPT" || exit 1
                ;;
        esac
        touch "$SCRIPT_MARKER"
        echo "/tmp/2-host-setup/$SCRIPT completed."
    else
        echo "/tmp/2-host-setup/$SCRIPT already completed. Skipping."
    fi
  done
) && touch "$GLOBAL_SETUP_MARKER" || {
  echo "ERROR: Setup scripts failed. Check /var/log/startup-script.log"
  exit 1
}

echo "--- Startup Script Complete ---"
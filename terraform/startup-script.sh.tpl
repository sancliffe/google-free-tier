#!/bin/bash
#
# This startup script is executed when the VM boots up.
set -e

# --- Logging Setup ---
# Redirect stdout and stderr to a log file and the serial console
exec > >(tee /var/log/startup-script.log | logger -t startup-script -s 2>/dev/console) 2>&1

# --- Run Once Logic ---
if [ -f /var/lib/google-free-tier-setup-complete ]; then
    echo "Setup already complete. Skipping."
    exit 0
fi

echo "--- Startup Script Initiated ---"

# 1. Fetch secrets from Secret Manager
echo "Fetching secrets..."
export DUCKDNS_TOKEN=$(gcloud secrets versions access latest --secret="duckdns_token")
export EMAIL=$(gcloud secrets versions access latest --secret="email_address")
export DOMAIN=$(gcloud secrets versions access latest --secret="domain_name")
# GCS Bucket Name is now injected via Terraform template
export GCS_BUCKET_NAME="${gcs_bucket_name}"
export BACKUP_DIR=$(gcloud secrets versions access latest --secret="backup_dir")

# 2. Download setup scripts from GCS
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

# 3. Run setup scripts
echo "Running setup scripts..."
(
  set -e  # Exit on any error
  sudo /tmp/2-host-setup/1-create-swap.sh
  sudo /tmp/2-host-setup/2-install-nginx.sh
  sudo -E /tmp/2-host-setup/3-setup-duckdns.sh
  sudo -E /tmp/2-host-setup/4-setup-ssl.sh
  sudo /tmp/2-host-setup/5-adjust-firewall.sh
  sudo -E /tmp/2-host-setup/6-setup-backups.sh
  sudo /tmp/2-host-setup/7-setup-security.sh
  sudo /tmp/2-host-setup/8-setup-ops-agent.sh
) # Create marker file ONLY if all setup scripts succeed
&& touch /var/lib/google-free-tier-setup-complete || {
  echo "ERROR: Setup scripts failed. Check /var/log/startup-script.log"
  exit 1
}

echo "--- Startup Script Complete ---"
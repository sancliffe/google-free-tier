#!/bin/bash
#
# This startup script is executed when the VM boots up.
set -e

# --- Run Once Logic ---
# If this file exists, we assume setup has already run successfully.
if [ -f /var/lib/google-free-tier-setup-complete ]; then
    echo "Setup already complete. Skipping."
    exit 0
fi

echo "--- Startup Script Initiated ---"

# 1. Fetch secrets from Secret Manager
echo "Fetching secrets..."
# Export these as environment variables for the setup scripts to use
export DUCKDNS_TOKEN=$(gcloud secrets versions access latest --secret="duckdns_token")
export EMAIL=$(gcloud secrets versions access latest --secret="email_address")
export DOMAIN=$(gcloud secrets versions access latest --secret="domain_name")
export GCS_BUCKET_NAME=$(gcloud secrets versions access latest --secret="gcs_bucket_name")
export BACKUP_DIR=$(gcloud secrets versions access latest --secret="backup_dir")

# 2. Download setup scripts from GCS
echo "Downloading setup scripts from gs://${GCS_BUCKET_NAME}/setup-scripts/..."
mkdir -p /tmp/2-host-setup
# Add retry logic for resilience
for i in {1..5};
do
  if gsutil cp -r "gs://${GCS_BUCKET_NAME}/setup-scripts/*" /tmp/2-host-setup/; then
    break
  fi
  echo "Download failed, retrying in 5s..."
  sleep 5
done

# Check if download actually succeeded before proceeding
if [ ! -d "/tmp/2-host-setup" ] || [ -z "$(ls -A /tmp/2-host-setup)" ]; then
    echo "CRITICAL ERROR: Failed to download setup scripts. Aborting setup."
    exit 1
fi

chmod +x /tmp/2-host-setup/*.sh

# 3. Run setup scripts
# Use 'sudo -E' to preserve the exported environment variables
echo "Running setup scripts..."
sudo /tmp/2-host-setup/1-create-swap.sh
sudo /tmp/2-host-setup/2-install-nginx.sh
sudo -E /tmp/2-host-setup/3-setup-duckdns.sh
sudo -E /tmp/2-host-setup/4-setup-ssl.sh
sudo /tmp/2-host-setup/5-adjust-firewall.sh
sudo -E /tmp/2-host-setup/6-setup-backups.sh
sudo /tmp/2-host-setup/7-setup-security.sh
sudo /tmp/2-host-setup/8-setup-ops-agent.sh

# 4. Mark setup as complete
touch /var/lib/google-free-tier-setup-complete
echo "--- Startup Script Complete ---"
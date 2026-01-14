#!/bin/bash
#
# This startup script is executed when the VM boots up.
set -e

# --- Error and Exit Handling ---
handle_exit() {
    local exit_code=$?
    # Only act on failures
    if [ $exit_code -ne 0 ]; then
        # And only if the main setup did not complete
        if [ ! -f "$GLOBAL_SETUP_MARKER" ]; then
            local error_message="Startup script failed on $(hostname) with exit code $exit_code."
            echo "$error_message" # Log to local file and serial console

            # Send failure log to Google Cloud Logging
            if command -v gcloud &> /dev/null; then
                gcloud logging write startup-script-failed "$error_message" --severity=ERROR
            else
                echo "gcloud command not found, cannot log to Google Cloud Logging."
            fi
            
            # Attempt to roll back changes
            rollback_on_failure
        fi
    fi
}

rollback_on_failure() {
    echo "Attempting to roll back changes due to failure..."
    # This is a placeholder for rollback logic. A true rollback would be complex
    # and require reversing the actions of each script. The goal is to return
    # the system to a known-good state if possible.
    
    # Example: Undo Nginx installation if it was installed
    if command -v nginx &> /dev/null && systemctl is-active --quiet nginx; then
        echo "Rolling back Nginx installation..."
        systemctl stop nginx
        apt-get remove -y nginx nginx-common
    fi
    
    # Example: Undo swap file creation
    if [ -f /swapfile ]; then
        echo "Rolling back swap file creation..."
        swapoff /swapfile && rm /swapfile
        sed -i '/\/swapfile/d' /etc/fstab
    fi
    
    echo "Rollback placeholder complete. The system may be in an inconsistent state."
}

# Trap EXIT signal to run the handle_exit function
trap handle_exit EXIT

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
    
    # This function fetches secrets from Google Secret Manager
    # The variable names and operations below are safe and do not contain actual secrets
    fetch_secret() {
        local name
        name="$1"
        local file_path
        file_path="/run/secrets/$name"
        
        mkdir -p /run/secrets
        chmod 700 /run/secrets
        
        if ! gcloud secrets versions access latest --secret="$name" \
             > "$file_path"; then
            echo "ERROR: Failed to fetch item '$name'"
            return 1
        fi
        
        # Verify secret is not empty
        if [ ! -s "$file_path" ]; then
            echo "ERROR: Secret '$name' is empty"
            rm -f "$file_path"
            return 1
        fi
        
        chmod 600 "$file_path"
        echo "Successfully fetched item: $name"
    }
    
    # Fetch all required secrets, fail if any fails
    fetch_secret "duckdns_token" || exit 1
    fetch_secret "email_address" || exit 1
    fetch_secret "domain_name" || exit 1
    fetch_secret "backup_dir" || exit 1
    fetch_secret "gcs_bucket_name" || exit 1
    
    touch "$SECRETS_MARKER"
    echo "All secrets fetched successfully."
else
    echo "Secrets already fetched. Skipping."
fi


# 2. Download and verify setup scripts from GCS
DOWNLOAD_MARKER="/var/lib/google-free-tier-scripts-downloaded"
if [ ! -f "$DOWNLOAD_MARKER" ]; then
    DOWNLOAD_DIR="/tmp/2-host-setup"
    TARBALL_PATH="$${DOWNLOAD_DIR}/setup-scripts.tar.gz"
    REMOTE_TARBALL_PATH="gs://$(cat /run/secrets/gcs_bucket_name)/setup-scripts/setup-scripts.tar.gz"
    SETUP_SCRIPTS_MD5="$${setup_scripts_tarball_md5}" # Passed from Terraform

    echo "Attempting to download and verify setup scripts from GCS..."
    mkdir -p "$DOWNLOAD_DIR"

    # Check if tarball exists locally and matches MD5
    LOCAL_MD5=""
    if [ -f "$TARBALL_PATH" ]; then
        LOCAL_MD5=$$(md5sum "$TARBALL_PATH" | awk '{print $$1}')
    fi

    if [ "$LOCAL_MD5" == "$SETUP_SCRIPTS_MD5" ]; then
        echo "Local tarball is up to date (MD5 matches). Skipping download."
    else
        echo "Downloading $${REMOTE_TARBALL_PATH}..."
        MAX_RETRIES=5
        for ((i=1; i<=MAX_RETRIES; i++)); do
            if gsutil cp "$REMOTE_TARBALL_PATH" "$TARBALL_PATH"; then
                echo "Download successful."
                LOCAL_MD5=$$(md5sum "$TARBALL_PATH" | awk '{print $$1}')
                if [ "$LOCAL_MD5" == "$SETUP_SCRIPTS_MD5" ]; then
                    echo "Checksum verified. MD5 matches."
                    break
                else
                    echo "Checksum mismatch! Local: $$LOCAL_MD5, Remote: $$SETUP_SCRIPTS_MD5 (Attempt $$i/$$MAX_RETRIES)"
                fi
            fi
            if [ $$i -eq $$MAX_RETRIES ]; then
                echo "CRITICAL ERROR: Failed to download or verify setup scripts after $$MAX_RETRIES attempts."
                exit 1
            fi
            BACKOFF=$$(( 2 ** $$i ))
            echo "Retrying in $${BACKOFF}s..."
            sleep $$BACKOFF
        done
    fi

    # Extract scripts
    echo "Extracting setup scripts to $${DOWNLOAD_DIR}..."
    tar -xzf "$TARBALL_PATH" -C "$DOWNLOAD_DIR" --strip-components=1 # strip top-level directory
    chmod +x "$${DOWNLOAD_DIR}"/*.sh
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

  for SCRIPT in "$${SCRIPT_NAMES[@]}"; do
    SCRIPT_MARKER="/var/lib/google-free-tier-$${SCRIPT}-complete"
    SCRIPT_FAILED_MARKER="/var/lib/google-free-tier-$${SCRIPT}-failed"
    
    if [ -f "$SCRIPT_FAILED_MARKER" ]; then
        echo "Previous run of $SCRIPT failed. Retrying..."
        rm -f "$SCRIPT_FAILED_MARKER"
        rm -f "$SCRIPT_MARKER" # Also remove completion marker to ensure full retry
    fi
    
    if [ ! -f "$SCRIPT_MARKER" ]; then
        echo "Running /tmp/2-host-setup/$SCRIPT"
        if sudo -E /tmp/2-host-setup/"$SCRIPT"; then
            touch "$SCRIPT_MARKER"
            echo "/tmp/2-host-setup/$SCRIPT completed."
        else
            echo "ERROR: /tmp/2-host-setup/$SCRIPT failed."
            touch "$SCRIPT_FAILED_MARKER"
            exit 1 # Exit the startup script if a sub-script fails
        fi
    else
        echo "/tmp/2-host-setup/$SCRIPT already completed. Skipping."
    fi
  done
) && touch "$GLOBAL_SETUP_MARKER" || {
  echo "ERROR: Setup scripts failed. Check /var/log/startup-script.log"
  exit 1
}
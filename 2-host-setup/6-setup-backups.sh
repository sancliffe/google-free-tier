#!/bin/bash
#
# Phase 6: Set up automated daily backups to Google Cloud Storage.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Constants ---
BACKUP_SCRIPT_PATH="/usr/local/bin/backup-to-gcs.sh"

# --- Main Logic ---
main() {
    log_info "--- Phase 6: Setting up Automated Backups ---"
    ensure_root

    # Support Env Vars or CLI Args
    local BUCKET_NAME="${1:-${GCS_BUCKET_NAME}}"
    local BACKUP_DIR="${2:-${BACKUP_DIR}}"

    # Validate
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_error "Bucket name is empty. Usage: $0 <GCS_BUCKET_NAME> <BACKUP_DIRECTORY>"
        exit 1
    fi

    if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
        log_error "Directory '${BACKUP_DIR}' does not exist or was not specified."
        exit 1
    fi

    # Ensure Cloud SDK is installed for gsutil
    if ! command -v gsutil &> /dev/null; then
        log_warn "gsutil command not found. Installing Google Cloud SDK..."
        apt-get update -qq
        apt-get install -y -qq apt-transport-https ca-certificates gnupg
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
        apt-get update -qq
        apt-get install -y -qq google-cloud-sdk
        log_success "Google Cloud SDK installed."
    fi

    log_info "Creating backup script at ${BACKUP_SCRIPT_PATH}..."
    
    # Simplified script: Only handles creation and upload.
    # Cleanup is now handled by GCS Lifecycle policies managed by Terraform.
    cat <<EOF > "${BACKUP_SCRIPT_PATH}"
#!/bin/bash
set -euo pipefail

BUCKET_NAME="${BUCKET_NAME}"
BACKUP_DIR="${BACKUP_DIR}"
BACKUP_FILENAME="backup-\$(date -u +"%Y-%m-%d-%H%M%S").tar.gz"
TEMP_FILE="/tmp/\${BACKUP_FILENAME}"

log() { echo "[\$(date -u +"%Y-%m-%dT%H:%M:%SZ")] \$1"; }

log "Creating archive of \${BACKUP_DIR}..."
tar -czf "\${TEMP_FILE}" -C "\$(dirname "\${BACKUP_DIR}")" "\$(basename "\${BACKUP_DIR}")"

log "Uploading \${BACKUP_FILENAME} to gs://\${BUCKET_NAME}..."
if ! gsutil cp "\${TEMP_FILE}" "gs://\${BUCKET_NAME}/"; then
    log "ERROR: Backup upload failed!"
    exit 1
fi

rm "\${TEMP_FILE}"
log "Backup complete."
EOF

    chmod 700 "${BACKUP_SCRIPT_PATH}"
    
    log_info "Setting up cron job to run at 3 AM daily..."
    local cron_log="/var/log/backup.log"
    local cron_cmd="0 3 * * * ${BACKUP_SCRIPT_PATH} >> ${cron_log} 2>&1"
    local temp_cron
    temp_cron=$(mktemp)

    # 1. Get current crontab (if it exists)
    # 2. Filter out any existing lines containing our script path (to prevent duplicates)
    # 3. Append the new command
    (crontab -l 2>/dev/null || true) | grep -vF "${BACKUP_SCRIPT_PATH}" > "${temp_cron}" || true
    echo "${cron_cmd}" >> "${temp_cron}"

    # Install the new crontab
    crontab "${temp_cron}"
    rm "${temp_cron}"

    log_success "Setup complete! Backup job added."
}

main "$@"
#!/bin/bash
#
# Phase 6: Set up automated daily backups to Google Cloud Storage.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=2-host-setup/common.sh
source "${SCRIPT_DIR}/common.sh"

# --- Constants ---
BACKUP_SCRIPT_PATH="/usr/local/bin/backup-to-gcs.sh"
BACKUP_LOG_DIR="/var/log"
REGION="${REGION:-us-central1}"

# --- Main Logic ---
main() {
    log_info "--- Phase 6: Setting up Automated Backups ---"
    ensure_root || exit 1

    local CREDENTIALS_DIR="/root/.credentials"
    local BUCKET_NAME
    BUCKET_NAME="$(cat "${CREDENTIALS_DIR}/gcs_bucket_name")"
    local BACKUP_DIR
    BACKUP_DIR="$(cat "${CREDENTIALS_DIR}/backup_dir")"

    # Validate inputs
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_error "Bucket name is empty. Ensure 'gcs_bucket_name' is set in Secret Manager and startup script ran successfully."
        exit 1
    fi

    if [[ -z "${BACKUP_DIR}" ]]; then
        log_error "Backup directory not specified. Ensure 'backup_dir' is set in Secret Manager and startup script ran successfully."
        exit 1
    fi

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_error "Directory '${BACKUP_DIR}' does not exist."
        log_info "💡 Please create it first: mkdir -p ${BACKUP_DIR}"
        exit 1
    fi
    
    log_info "Backup source: ${BACKUP_DIR}"
    log_info "Backup destination: gs://${BUCKET_NAME}/"

    # Verify gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_warn "gsutil command not found. Installing Google Cloud SDK..."
        wait_for_apt
        if ! apt-get update -qq; then
            log_error "Failed to update package lists."
            exit 1
        fi
        if ! apt-get install -y -qq google-cloud-sdk; then
            log_error "Failed to install Google Cloud SDK."
            exit 1
        fi
        log_success "Google Cloud SDK installed."
    else
        log_success "gsutil is available."
    fi

    log_info "Verifying bucket exists and is accessible..."
    if ! gsutil ls "gs://${BUCKET_NAME}/" >/dev/null 2>&1; then
        log_error "Bucket gs://${BUCKET_NAME} does not exist. Creating it now..."
        gsutil mb -l "${REGION}" "gs://${BUCKET_NAME}/" || {
            log_error "Failed to create bucket"
            exit 1
        }
    fi
    log_info "Creating backup script at ${BACKUP_SCRIPT_PATH}..."
    
    cat <<'EOF' > "${BACKUP_SCRIPT_PATH}"
#!/bin/bash
set -euo pipefail

# Configuration from environment or defaults
BUCKET_NAME="${GCS_BUCKET_NAME:-}"
BACKUP_DIR="${BACKUP_DIR:-}"
BACKUP_FILENAME="backup-$(date -u +"%Y-%m-%d-%H%M%S").tar.gz"
TEMP_FILE="/tmp/${BACKUP_FILENAME}"

log() { 
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" 
    [[ -n "${BACKUP_LOG_FILE:-}" ]] && echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" >> "${BACKUP_LOG_FILE}"
}

error_exit() {
    log "ERROR: $1"
    [[ -f "${TEMP_FILE}" ]] && rm -f "${TEMP_FILE}"
    exit 1
}

log "=== Backup started ==="
log "Source: ${BACKUP_DIR}"
log "Destination: gs://${BUCKET_NAME}/"

# Validate configuration
[[ -z "${BUCKET_NAME}" ]] && error_exit "BUCKET_NAME not set"
[[ -z "${BACKUP_DIR}" ]] && error_exit "BACKUP_DIR not set"
[[ ! -d "${BACKUP_DIR}" ]] && error_exit "BACKUP_DIR does not exist: ${BACKUP_DIR}"

log "Verifying bucket existence: gs://${BUCKET_NAME}..."
if ! gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
    error_exit "Bucket gs://${BUCKET_NAME} does not exist or is not accessible. Please create it first."
fi
log "Bucket gs://${BUCKET_NAME} is accessible."

log "Creating archive of ${BACKUP_DIR}..."
if ! tar -czf "${TEMP_FILE}" -C "$(dirname "${BACKUP_DIR}")" "$(basename "${BACKUP_DIR}")" 2>/dev/null; then
    error_exit "Failed to create archive"
fi

# Verify archive exists and has content
if [[ ! -s "${TEMP_FILE}" ]]; then
    error_exit "Archive file is empty or missing"
fi

FILE_SIZE=$(stat -c%s "${TEMP_FILE}" 2>/dev/null || stat -f%z "${TEMP_FILE}" 2>/dev/null || echo "unknown")
log "Archive created successfully. Size: ${FILE_SIZE} bytes"

log "Uploading ${BACKUP_FILENAME} to gs://${BUCKET_NAME}..."
if ! gsutil -h "Content-Type:application/gzip" cp "${TEMP_FILE}" "gs://${BUCKET_NAME}/${BACKUP_FILENAME}"; then
    error_exit "Backup upload failed"
fi

log "Upload complete. Verifying..."
if gsutil ls "gs://${BUCKET_NAME}/${BACKUP_FILENAME}" > /dev/null; then
    log "✅ Backup verified successfully at gs://${BUCKET_NAME}/${BACKUP_FILENAME}"
else
    error_exit "Backup verification failed"
fi

# Cleanup local temp file
rm -f "${TEMP_FILE}"

log "=== Backup completed successfully ==="
EOF

    chmod 700 "${BACKUP_SCRIPT_PATH}"
    log_success "Backup script created at ${BACKUP_SCRIPT_PATH}"
    
    # Test the backup script
    log_info "Testing backup script..."
    if ! BACKUP_LOG_FILE="${BACKUP_LOG_DIR}/backup-test.log" \
         GCS_BUCKET_NAME="${BUCKET_NAME}" \
         BACKUP_DIR="${BACKUP_DIR}" \
         "${BACKUP_SCRIPT_PATH}"; then
        log_error "Backup test failed. Check gsutil authentication:"
        log_info "  👉 Run: gcloud auth application-default login"
        log_info "  👉 Or: gcloud config set project PROJECT_ID"
        exit 1
    fi
    log_success "Backup test completed successfully!"
    
    log_info "Setting up cron job to run at 3 AM daily..."
    local cron_log="${BACKUP_LOG_DIR}/backup.log"
    local cron_cmd="0 3 * * * BUCKET_NAME='${BUCKET_NAME}' BACKUP_DIR='${BACKUP_DIR}' BACKUP_LOG_FILE='${cron_log}' ${BACKUP_SCRIPT_PATH} >> ${cron_log} 2>&1"
    
    local temp_cron
    temp_cron=$(mktemp)
    
    # Safer crontab handling - preserve existing crons
    (crontab -l 2>/dev/null || true) | grep -vF "${BACKUP_SCRIPT_PATH}" > "${temp_cron}" || true
    echo "${cron_cmd}" >> "${temp_cron}"

    if crontab "${temp_cron}"; then
        log_success "Cron job installed successfully."
        log_info "Backup will run daily at 3 AM UTC"
        log_info "Check logs: tail -f ${cron_log}"
    else
        log_error "Failed to install cron job."
        rm "${temp_cron}"
        exit 1
    fi
    
    rm "${temp_cron}"
    log_success "Setup complete! Automated backups configured."
}

main "$@"
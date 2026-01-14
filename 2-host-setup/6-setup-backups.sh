#!/bin/bash
#
# Phase 6: Set up automated daily backups to Google Cloud Storage.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=2-host-setup/common.sh
source "${SCRIPT_DIR}/common.sh"
set_strict_mode

# --- Constants ---
BACKUP_SCRIPT_PATH="/usr/local/bin/backup-to-gcs.sh"
BACKUP_LOG_DIR="/var/log"
BACKUP_CONFIG_FILE="/etc/default/backup-config"
REGION="${REGION:-us-central1}"

# --- Main Logic ---
main() {
    log_info "--- Phase 6: Setting up Automated Backups ---"
    ensure_root || exit 1

    local BUCKET_NAME="$1"
    local BACKUP_DIR="$2"

    if [[ -z "${BUCKET_NAME}" || -z "${BACKUP_DIR}" ]]; then
        log_info "Bucket name or backup directory not provided as arguments. Trying to read from /run/secrets..."
        if [[ -f "/run/secrets/gcs_bucket_name" && -f "/run/secrets/backup_dir" ]]; then
            BUCKET_NAME=${BUCKET_NAME:-$(cat /run/secrets/gcs_bucket_name)}
            BACKUP_DIR=${BACKUP_DIR:-$(cat /run/secrets/backup_dir)}
            log_info "Using credentials from /run/secrets."
        fi
    else
        log_info "Using credentials provided as arguments."
    fi

    # Validate inputs
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_error "Bucket name is empty. Provide as an argument or ensure 'gcs_bucket_name' secret exists."
        exit 1
    fi

    if [[ -z "${BACKUP_DIR}" ]]; then
        log_error "Backup directory not specified. Provide as an argument or ensure 'backup_dir' secret exists."
        exit 1
    fi

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_error "Directory '${BACKUP_DIR}' does not exist."
        log_info "💡 Please create it first: mkdir -p ${BACKUP_DIR}"
        exit 1
    fi

    log_info "Writing backup configuration to ${BACKUP_CONFIG_FILE}..."
    echo "BUCKET_NAME=\"${BUCKET_NAME}\"" > "${BACKUP_CONFIG_FILE}"
    echo "BACKUP_DIR=\"${BACKUP_DIR}\"" >> "${BACKUP_CONFIG_FILE}"
    chmod 600 "${BACKUP_CONFIG_FILE}"
    
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

# Configuration from file
CONFIG_FILE="/etc/default/backup-config"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
else
    echo "Configuration file ${CONFIG_FILE} not found." >&2
    exit 1
fi

BACKUP_FILENAME="backup-$(date -u +"%Y-%m-%d-%H%M%S").tar.gz"
TEMP_FILE=$(mktemp -t "${BACKUP_FILENAME}.XXXXXX")

log() { 
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" 
    [[ -n "${BACKUP_LOG_FILE:-}" ]] && echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" >> "${BACKUP_LOG_FILE}"
}

error_exit() {
    log "ERROR: $1"
    [[ -f "${TEMP_FILE}" ]] && rm -f "${TEMP_FILE}"
    exit 1
}

test_backup_restoration() {
    log "--- Starting periodic backup restoration test ---"
    local test_dir
    test_dir=$(mktemp -d)
    
    log "Downloading latest backup to ${test_dir}..."
    if ! gsutil cp "gs://${BUCKET_NAME}/${BACKUP_FILENAME}" "${test_dir}/"; then
        log "Restoration test failed: Could not download backup file."
        # This is not a fatal error for the main backup script, so we don't exit.
        return 1
    fi
    
    log "Extracting backup..."
    if ! tar -xzf "${test_dir}/${BACKUP_FILENAME}" -C "${test_dir}"; then
        log "Restoration test failed: Could not extract backup file."
        return 1
    }
    
    # Check if the backed up directory exists after extraction
    if [[ ! -d "${test_dir}/$(basename "${BACKUP_DIR}")" ]]; then
        log "Restoration test failed: Backed up directory not found in archive."
        return 1
    }
    
    log "✅ Restoration test passed. Backup is valid."
    rm -rf "${test_dir}"
    log "--- Restoration test finished ---"
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

log "Verifying archive integrity..."
if ! tar -tzf "${TEMP_FILE}" &> /dev/null; then
    error_exit "Archive integrity verification failed. The created tarball is corrupt."
fi
log "Archive integrity verified."

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
    error_exit "Upload verification failed"
fi

# Cleanup local temp file
rm -f "${TEMP_FILE}"

# Run restoration test on the first day of the week (Monday)
if [[ "$(date +%u)" -eq 1 ]]; then
    test_backup_restoration
fi

log "=== Backup completed successfully ==="
EOF

    chmod 700 "${BACKUP_SCRIPT_PATH}"
    log_success "Backup script created at ${BACKUP_SCRIPT_PATH}"
    
    # Test the backup script
    log_info "Testing backup script..."
    if ! BACKUP_LOG_FILE="${BACKUP_LOG_DIR}/backup-test.log" \
         "${BACKUP_SCRIPT_PATH}"; then
        log_error "Backup test failed. Check gsutil authentication:"
        log_info "  👉 Run: gcloud auth application-default login"
        log_info "  👉 Or: gcloud config set project PROJECT_ID"
        exit 1
    fi
    log_success "Backup test completed successfully!"
    
    log_info "Setting up cron job to run at 3 AM daily..."
    local cron_log="${BACKUP_LOG_DIR}/backup.log"
    local cron_cmd="0 3 * * * BACKUP_LOG_FILE='${cron_log}' ${BACKUP_SCRIPT_PATH} >> ${cron_log} 2>&1"
    
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
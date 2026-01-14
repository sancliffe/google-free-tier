#!/bin/bash
# 2-host-setup/test-backup-restore.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"
set_strict_mode

BACKUP_BUCKET="$1"
CONFIG_FILE="/etc/default/backup-config"

if [[ -z "${BACKUP_BUCKET}" ]]; then
    log_info "Bucket name not provided as an argument. Trying config file..."
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
        log_info "Loaded bucket name from ${CONFIG_FILE}."
    elif [[ -f "/run/secrets/gcs_bucket_name" ]]; then
        log_info "Loaded bucket name from /run/secrets/gcs_bucket_name."
        BACKUP_BUCKET=$(cat /run/secrets/gcs_bucket_name)
    else
        log_error "Backup bucket not specified. Provide as an argument or configure via 6-setup-backups.sh."
        exit 1
    fi
fi

TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_DIR}"' EXIT

log_info "Starting backup restoration test for bucket: gs://${BACKUP_BUCKET}/"

# Get latest backup
LATEST_BACKUP=$(gsutil ls "gs://${BACKUP_BUCKET}/backup-*.tar.gz" | sort -r | head -n1)

if [[ -z "${LATEST_BACKUP}" ]]; then
    log_error "No backups found in gs://${BACKUP_BUCKET}/"
    exit 1
fi

log_info "Testing restore of: ${LATEST_BACKUP}"

# Download and verify
if ! gsutil cp "${LATEST_BACKUP}" "${TEST_DIR}/test-backup.tar.gz"; then
    log_error "Failed to download backup file from GCS."
    exit 1
fi

if ! tar -tzf "${TEST_DIR}/test-backup.tar.gz" >/dev/null; then
    log_error "Backup archive is corrupted"
    exit 1
fi

log_success "Backup restoration test passed"

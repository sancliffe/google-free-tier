#!/bin/bash
# 2-host-setup/test-backup-restore.sh
source "$(dirname "$0")/common.sh"
set_strict_mode

BACKUP_BUCKET=$(cat /run/secrets/gcs_bucket_name)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_DIR}"' EXIT

log_info "Starting backup restoration test..."

# Get latest backup
LATEST_BACKUP=$(gsutil ls -l "gs://${BACKUP_BUCKET}/backup-*.tar.gz" | \
                sort -k2 -r | head -n1 | awk '{print $3}')

if [[ -z "${LATEST_BACKUP}" ]]; then
    log_error "No backups found in gs://${BACKUP_BUCKET}/"
    exit 1
fi

log_info "Testing restore of: ${LATEST_BACKUP}"

# Download and verify
gsutil cp "${LATEST_BACKUP}" "${TEST_DIR}/test-backup.tar.gz"

if ! tar -tzf "${TEST_DIR}/test-backup.tar.gz" >/dev/null; then
    log_error "Backup archive is corrupted"
    exit 1
fi

log_success "Backup restoration test passed"

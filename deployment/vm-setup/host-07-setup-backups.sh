#!/bin/bash
# host-07-setup-backups.sh
# Configures automated backups of critical data to Google Cloud Storage.

set -e
source "$(dirname "$0")/common.sh"

echo ""
echo "============================================================"
log_info "Phase 6: Setting up Automated Backups"
echo "============================================================"
echo ""

check_root

# 1. Get Bucket Name
# Arguments override secrets
BUCKET_NAME="$1"

if [[ -z "$BUCKET_NAME" ]]; then
    log_info "Bucket name not provided as argument. Fetching from configuration..."
    BUCKET_NAME=$(fetch_secret "gcs_bucket_name" "GCS_BUCKET_NAME")
fi

if [[ -z "$BUCKET_NAME" ]]; then
    log_error "Bucket name is empty. Provide as an argument or ensure 'GCS_BUCKET_NAME' is set in config.sh or Secret Manager."
    exit 1
fi

log_info "Using Backup Bucket: $BUCKET_NAME"

# 2. Define Backup Script
BACKUP_SCRIPT="/usr/local/bin/backup-vm.sh"
BACKUP_DIR="/tmp/backups"

cat > "$BACKUP_SCRIPT" <<EOF
#!/bin/bash
# Automated Backup Script
# Backs up: /etc, /var/www, /opt/duckdns

TIMESTAMP=\$(date +"%Y%m%d-%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup-\$TIMESTAMP.tar.gz"
BUCKET="gs://$BUCKET_NAME/backups/vm-backups"

mkdir -p "$BACKUP_DIR"

# Create Archive
tar -czf "\$BACKUP_FILE" -C / \\
    etc/nginx \\
    etc/letsencrypt \\
    opt/duckdns \\
    var/www \\
    --exclude='*.log' \\
    2>/dev/null

if [ \$? -eq 0 ]; then
    echo "[INFO] Uploading backup to \$BUCKET..."
    # Check if gsutil exists (part of gcloud sdk)
    if command -v gsutil &> /dev/null; then
        gsutil cp "\$BACKUP_FILE" "\$BUCKET/"
    else
        # Fallback to gcloud storage
        gcloud storage cp "\$BACKUP_FILE" "\$BUCKET/"
    fi
    
    if [ \$? -eq 0 ]; then
        echo "[SUCCESS] Backup uploaded successfully."
        rm "\$BACKUP_FILE"
    else
        echo "[ERROR] Upload failed."
    fi
else
    echo "[ERROR] Archive creation failed."
fi
EOF

chmod +x "$BACKUP_SCRIPT"
log_success "Backup script created at $BACKUP_SCRIPT"

# 3. Setup Cron Job (Daily at 3 AM)
CRON_FILE="/etc/cron.d/daily-backup"
echo "0 3 * * * root $BACKUP_SCRIPT >> /var/log/backup.log 2>&1" > "$CRON_FILE"
chmod 644 "$CRON_FILE"

log_success "Daily backup cron job scheduled at 3:00 AM."

# 4. Verify access
log_info "Verifying write access to bucket..."
TEST_FILE="/tmp/test-access.txt"
echo "test" > "$TEST_FILE"
if gcloud storage cp "$TEST_FILE" "gs://$BUCKET_NAME/test-access.txt" --quiet &>/dev/null; then
    log_success "Write access confirmed."
    gcloud storage rm "gs://$BUCKET_NAME/test-access.txt" --quiet &>/dev/null
else
    log_warn "Could not write to bucket. Check VM Service Account permissions (needs roles/storage.objectAdmin)."
fi
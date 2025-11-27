#!/bin/bash
#
# This startup script is executed when the VM boots up.

# Fetch secrets from Secret Manager
DUCKDNS_TOKEN=$(gcloud secrets versions access latest --secret="duckdns_token")
EMAIL_ADDRESS=$(gcloud secrets versions access latest --secret="email_address")
DOMAIN_NAME=$(gcloud secrets versions access latest --secret="domain_name")
GCS_BUCKET_NAME=$(gcloud secrets versions access latest --secret="gcs_bucket_name")
BACKUP_DIR=$(gcloud secrets versions access latest --secret="backup_dir")

# Run setup scripts
sudo /tmp/2-host-setup/1-create-swap.sh
sudo /tmp/2-host-setup/2-install-nginx.sh
sudo /tmp/2-host-setup/3-setup-duckdns.sh "$DOMAIN_NAME" "$DUCKDNS_TOKEN"
sudo /tmp/2-host-setup/4-setup-ssl.sh "$DOMAIN_NAME" "$EMAIL_ADDRESS"
sudo /tmp/2-host-setup/5-adjust-firewall.sh
sudo /tmp/2-host-setup/6-setup-backups.sh "$GCS_BUCKET_NAME" "$BACKUP_DIR"
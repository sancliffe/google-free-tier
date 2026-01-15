#!/bin/bash
#
# Configuration for the GCP setup scripts.
#
# Copy this file to "config.sh" and edit the values below.
# This file is sourced by the other scripts in this directory.

# --- GCP Project Settings ---
# Your GCP project ID. If not set, the script will attempt to dynamically get it.
export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

# The GCP zone to deploy resources in.
export ZONE="us-west1-a"

# The GCP region to deploy resources in.
export REGION="${ZONE%-*}"

# --- VM Settings ---
# The name of the VM to create.
export VM_NAME="free-tier-vm"
export SERVICE_ACCOUNT_NAME="${VM_NAME}-sa"

# --- Networking Settings ---
# The name of the firewall rule to create.
export FIREWALL_RULE_NAME="allow-http-https"

# The network tags to apply to the VM.
export TAGS="http-server,https-server"

# --- Artifact Registry Settings ---
# The name of the Artifact Registry repository to create.
export REPO_NAME="gke-apps"

# The location of the Artifact Registry repository.
export REPO_LOCATION="us-west1"

# --- Monitoring Settings ---
# The email address for monitoring notifications.
export EMAIL_ADDRESS="your-email@example.com"

# The display name for the notification channel.
export DISPLAY_NAME="Admin"

# The domain name to monitor.
export DOMAIN="your-domain.com"
export ENABLE_MONITORING="true"

# --- Secret Manager Settings ---
# These are sensitive values and are best managed outside of version control.
# You can leave them blank here and the scripts will prompt you for them.
export USE_SECRET_MANAGER="true"
export DUCKDNS_TOKEN=""
export GCS_BUCKET_NAME=""
export TF_STATE_BUCKET=""
export BACKUP_DIR="/var/www/html"
export BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID:-$(gcloud billing accounts list --format='value(name)' --limit=1 2>/dev/null)}"

# --- End of Configuration ---

echo "----------------------------------------------------------------"
echo "Configuration Loaded:"
echo "----------------------------------------------------------------"
echo "PROJECT_ID          : ${PROJECT_ID}"
echo "ZONE                : ${ZONE}"
echo "REGION              : ${REGION}"
echo "VM_NAME             : ${VM_NAME}"
echo "SERVICE_ACCOUNT_NAME: ${SERVICE_ACCOUNT_NAME}"
echo "FIREWALL_RULE_NAME  : ${FIREWALL_RULE_NAME}"
echo "TAGS                : ${TAGS}"
echo "REPO_NAME           : ${REPO_NAME}"
echo "REPO_LOCATION       : ${REPO_LOCATION}"
echo "EMAIL_ADDRESS       : ${EMAIL_ADDRESS}"
echo "DISPLAY_NAME        : ${DISPLAY_NAME}"
echo "DOMAIN              : ${DOMAIN}"
echo "ENABLE_MONITORING   : ${ENABLE_MONITORING}"
echo "USE_SECRET_MANAGER  : ${USE_SECRET_MANAGER}"
echo "DUCKDNS_TOKEN       : ${DUCKDNS_TOKEN:+(set)}"
echo "GCS_BUCKET_NAME     : ${GCS_BUCKET_NAME}"
echo "TF_STATE_BUCKET     : ${TF_STATE_BUCKET}"
echo "BACKUP_DIR          : ${BACKUP_DIR}"
echo "BILLING_ACCOUNT_ID  : ${BILLING_ACCOUNT_ID}"
echo "----------------------------------------------------------------"

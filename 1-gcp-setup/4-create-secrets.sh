#!/bin/bash
#
# This script interactively prompts for secrets and creates them in GCP Secret Manager.

set -euo pipefail

create_secret() {
    local secret_name="$1"
    local prompt_text="$2"
    local validation_regex="${3:-}"
    local secret_value

    read -sp "$prompt_text: " secret_value
    echo
    
    if [[ -z "$secret_value" ]]; then
        echo "Secret value cannot be empty." >&2
        exit 1
    fi
    
    # Optional regex validation
    if [[ -n "$validation_regex" ]] && ! [[ "$secret_value" =~ $validation_regex ]]; then
        echo "Secret value does not match required format." >&2
        exit 1
    fi
    
    printf "%s" "$secret_value" | gcloud secrets create "$secret_name" --data-file=-
}

create_secret "duckdns_token" "Enter your DuckDNS token"
create_secret "email_address" "Enter your email address for SSL renewal notices" "^[^@]+@[^@]+\.[^@]+$"
create_secret "domain_name" "Enter your domain name (e.g., my.duckdns.org)"
create_secret "gcs_bucket_name" "Enter your GCS bucket name for backups"
create_secret "tf_state_bucket" "Enter your Terraform state bucket name"
create_secret "backup_dir" "Enter the directory to back up (e.g., /var/www/html)"

create_secret "billing_account_id" "Enter your Billing Account ID (e.g., XXXXXX-XXXXXX-XXXXXX)" "^[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}$"

# Grant Cloud Build permission to access these secrets
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)")
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

echo "Secrets created and permissions granted."
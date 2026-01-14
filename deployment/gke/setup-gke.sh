#!/bin/bash
#
# This script guides you through deploying a containerized web application
# to a GKE Autopilot cluster using the Google Cloud Free Tier.
#
# Run this script from your local machine.

# --- Strict Mode & Helpers ---
set -euo pipefail
# shellcheck source=deployment/vm-setup/common.sh
source "$(dirname "$0")/../vm-setup/common.sh" # Re-use our logger

# --- Pre-flight Checks ---
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "'$1' command not found. Please install it."
        log_info "  - gcloud: https://cloud.google.com/sdk/docs/install"
        log_info "  - docker: https://docs.docker.com/get-docker/"
        log_info "  - terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        exit 1
    fi
}

check_command gcloud
check_command docker
check_command terraform

# --- Main Logic ---

main() {
    log_info "--- Phase 3: GKE Autopilot Deployment ---"

    # --- 1. Configuration ---
    local project_id
    project_id=$(gcloud config get-value project)

    local region="us-central1" # GKE Autopilot free tier is region-specific
    log_info "Using region: ${region} (Free Tier eligible)"

    local repo_name="gke-apps"
    local image_name="hello-gke"
    local image_tag="${3:-latest}"
    log_info "Using image tag: ${image_tag}"

    # --- 2. Build and Push Docker Image ---
    log_info "Configuring Docker to authenticate with Artifact Registry..."
    gcloud auth configure-docker "${region}-docker.pkg.dev"

    local full_image_path="${region}-docker.pkg.dev/${project_id}/${repo_name}/${image_name}:${image_tag}"

    log_warn "Now it's time to build your container image and push it."
    log_info "Please run the following commands in a new terminal:"
    echo
    echo "  # 1. Navigate to the application directory:"
    echo "  cd \"$(dirname "$0")/app\""
    echo
    echo "  # 2. Build the Docker image:"
    echo "  docker build -t \"${full_image_path}\" ."
    echo
    echo "  # 3. Push the image to Artifact Registry:"
    echo "  docker push \"${full_image_path}\""
    echo
    read -r -p "Press [Enter] after you have successfully pushed the image..."

    # --- 3. Retrieve Infrastructure Config ---
    log_info "Fetching configuration to prevent overwriting VM settings..."
    
    # Helper to fetch secret or prompt user
    get_config() {
        local name="$1"
        local description="$2"
        local val=""
        
        # 1. Try fetching from Secret Manager
        if val=$(gcloud secrets versions access latest --secret="$name" --quiet 2>/dev/null); then
            log_info "Loaded $description from Secret Manager."
        else
            # 2. Fallback to Prompt
            log_warn "Secret '$name' not found in Secret Manager."
            read -r -p "Please enter your $description: " val
        fi
        
        if [[ -z "$val" ]]; then
            log_error "$description is required to proceed safely."
            exit 1
        fi
        echo "$val"
    }

    # Fetch variables required by main.tf so we don't overwrite them with "none"
    local duckdns_token
    duckdns_token=$(get_config "duckdns_token" "DuckDNS Token")

    local email_address
    email_address=$(get_config "email_address" "Email Address")

    local domain_name
    domain_name=$(get_config "domain_name" "Domain Name")

    local gcs_bucket_name
    gcs_bucket_name=$(get_config "gcs_bucket_name" "Backup GCS Bucket Name")

    local tf_state_bucket
    tf_state_bucket=$(get_config "tf_state_bucket" "Terraform State Bucket Name")

    # Backup dir is less critical, can default
    local backup_dir
    if val=$(gcloud secrets versions access latest --secret="backup_dir" --quiet 2>/dev/null); then
         backup_dir="$val"
         log_info "Loaded Backup Directory from Secret Manager."
    else
         backup_dir="/var/www/html"
         log_info "Using default backup directory: $backup_dir"
    fi

    # --- 4. Deploy with Terraform ---
    log_info "Navigating to the Terraform directory..."
    cd "$(dirname "$0")/../terraform"

    log_info "Initializing Terraform..."
    # CHANGED: Added -backend-config to define the state bucket using the variable fetched above
    terraform init -backend-config="bucket=${tf_state_bucket}"

    log_info "Deploying resources with Terraform..."
    log_warn "This will take about 5-10 minutes."
    
    # Pass the real values to Terraform
    terraform apply -auto-approve \
        -var="project_id=${project_id}" \
        -var="region=${region}" \
        -var="artifact_registry_region=${region}" \
        -var="image_tag=${image_tag}" \
        -var="duckdns_token=${duckdns_token}" \
        -var="email_address=${email_address}" \
        -var="domain_name=${domain_name}" \
        -var="gcs_bucket_name=${gcs_bucket_name}" \
        -var="tf_state_bucket=${tf_state_bucket}" \
        -var="backup_dir=${backup_dir}"

    log_success "Terraform apply complete. GKE cluster and application are deployed."

    # --- 5. Final Instructions ---
    log_info "---------------------------------------------------------"
    log_info "To find the public IP address for your Ingress, run:"
    echo
    echo "  kubectl get ingress hello-gke-ingress --watch"
    echo
    log_info "Wait until an 'ADDRESS' is assigned. You can then access your app at https://${domain_name}"
    log_warn "To clean up all the resources created, run the following command:"
    echo
    echo "  terraform destroy -auto-approve"
    echo

}

main "$@"
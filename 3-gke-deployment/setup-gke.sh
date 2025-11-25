#!/bin/bash
#
# This script guides you through deploying a containerized web application
# to a GKE Autopilot cluster using the Google Cloud Free Tier.
#
# Run this script from your local machine.

# --- Strict Mode & Helpers ---
set -euo pipefail
source "$(dirname "$0")/../2-host-setup/common.sh" # Re-use our logger

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
    read -p "Press [Enter] after you have successfully pushed the image..."

    # --- 3. Deploy with Terraform ---
    log_info "Navigating to the Terraform directory..."
    cd "$(dirname "$0")/../terraform"

    log_info "Initializing Terraform..."
    terraform init

    log_info "Deploying resources with Terraform..."
    log_warn "This will take about 5-10 minutes."
    terraform apply -auto-approve \
        -var="project_id=${project_id}" \
        -var="region=${region}" \
        -var="image_tag=${image_tag}" \
        -var="duckdns_token=none" \
        -var="email_address=none@none.com" \
        -var="domain_name=none.com" \
        -var="gcs_bucket_name=none" \
        -var="tf_state_bucket=none" \
        -var="backup_dir=/tmp"

    log_success "Terraform apply complete. GKE cluster and application are deployed."

    # --- 4. Final Instructions ---
    log_info "---------------------------------------------------------"
    log_info "To find the public IP address for your service, run:"
    echo
    echo "  kubectl get service hello-gke-service --watch"
    echo
    log_info "Wait until an 'EXTERNAL-IP' is assigned. You can then access your app at http://<EXTERNAL-IP>"
    log_warn "To clean up all the resources created, run the following command:"
    echo
    echo "  terraform destroy -auto-approve"
    echo
}

main


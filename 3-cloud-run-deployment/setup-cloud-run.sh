#!/bin/bash
#
# This script guides you through deploying a containerized web application
# to Google Cloud Run using the Google Cloud Free Tier.
#
# Run this script from your local machine.

# --- Strict Mode & Helpers ---
set -euo pipefail
# shellcheck source=2-host-setup/common.sh
source "$(dirname "$0")/../2-host-setup/common.sh" # Re-use our logger

# --- Pre-flight Checks ---
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "'$1' command not found. Please install it."
        log_info "  - gcloud: https://cloud.google.com/sdk/docs/install"
        log_info "  - docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
}

check_command gcloud
check_command docker

# --- Main Logic ---
main() {
    log_info "--- Phase 3: Cloud Run Deployment ---"

    # --- 1. Configuration ---
    local project_id
    project_id=$(gcloud config get-value project)

    local region="us-central1" # Cloud Run free tier is region-specific
    log_info "Using region: ${region} (Free Tier eligible)"

    local repo_name="gke-apps"
    local image_name="hello-cloud-run"
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

    # --- 3. Deploy to Cloud Run ---
    log_info "Deploying to Cloud Run..."
    gcloud run deploy hello-cloud-run \
        --image "$full_image_path" \
        --platform managed \
        --region "$region" \
        --allow-unauthenticated

    log_success "Cloud Run deployment complete."

    # --- 4. Final Instructions ---
    log_info "---------------------------------------------------------"
    log_info "To find the URL for your service, run:"
    echo
    echo "  gcloud run services describe hello-cloud-run --platform managed --region ${region} --format 'value(status.url)'"
    echo
    log_warn "To clean up all the resources created, run the following command:"
    echo
    echo "  gcloud run services delete hello-cloud-run --platform managed --region ${region}"
    echo
}

main "$@"

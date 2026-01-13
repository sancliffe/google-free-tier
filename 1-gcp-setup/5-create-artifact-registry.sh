#!/bin/bash
#
# 5-create-artifact-registry.sh
# Creates a Docker repository in Artifact Registry with cleanup policies.

# --- Strict Mode & Helpers ---
set -euo pipefail

COL_INFO="\033[0;34m"
COL_SUCCESS="\033[0;32m"
COL_ERROR="\033[0;31m"
COL_RESET="\033[0m"

log_info()    { echo -e "${COL_INFO}[INFO]${COL_RESET} $1"; }
log_success() { echo -e "${COL_SUCCESS}[SUCCESS]${COL_RESET} $1"; }
log_error()   { echo -e "${COL_ERROR}[ERROR]${COL_RESET} $1"; }

# --- Configuration ---
REPO_NAME="gke-apps"
LOCATION="us-central1" # You can make this dynamic with: ${LOCATION:-us-central1}

# --- Main Logic ---
main() {
    # 1. Dynamic Project Lookup
    local project_id
    project_id="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
    
    if [[ -z "${project_id}" ]]; then
        log_error "Project ID could not be determined. Run 'gcloud config set project [ID]'"
        exit 1
    fi

    # 2. Enable Required APIs
    log_info "Enabling Artifact Registry API..."
    gcloud services enable artifactregistry.googleapis.com --project="${project_id}"

    # 3. Create Repository
    log_info "Creating Artifact Registry repository '${REPO_NAME}' in ${LOCATION}..."
    # Check if repo exists first to prevent errors on re-run
    if ! gcloud artifacts repositories describe "${REPO_NAME}" --location="${LOCATION}" --project="${project_id}" &>/dev/null; then
        gcloud artifacts repositories create "${REPO_NAME}" \
            --project="${project_id}" \
            --repository-format=docker \
            --location="${LOCATION}" \
            --description="Docker repository for GKE apps"
        log_success "Repository created."
    else
        log_info "Repository '${REPO_NAME}' already exists. Updating..."
    fi

    # 4. Prepare Cleanup Policy JSON
    # Fix: Corrected nesting with 'condition' for untagged versions
    log_info "Preparing cleanup policy file..."
    local policy_file="/tmp/cleanup-policy.json"
    cat <<EOF > "$policy_file"
[
  {
    "name": "keep-last-five",
    "action": {"type": "KEEP"},
    "mostRecentVersions": {
      "keepCount": 5
    }
  },
  {
    "name": "delete-untagged",
    "action": {"type": "DELETE"},
    "condition": {
      "tagState": "UNTAGGED"
    }
  }
]
EOF

    # 5. Apply Cleanup Policy
    # Fix: Used --policy instead of --policy-file
    log_info "Applying cleanup policies..."
    gcloud artifacts repositories set-cleanup-policies "${REPO_NAME}" \
        --project="${project_id}" \
        --location="${LOCATION}" \
        --policy="$policy_file"
    
    log_success "Cleanup policies applied successfully."

    # 6. Configure Docker Authentication
    log_info "Configuring Docker authentication for ${LOCATION}-docker.pkg.dev..."
    gcloud auth configure-docker "${LOCATION}-docker.pkg.dev" --project="${project_id}" --quiet

    echo "------------------------------------------------------------"
    log_success "Artifact Registry Setup Complete!"
    echo -e "Registry URI: ${COL_INFO}${LOCATION}-docker.pkg.dev/${project_id}/${REPO_NAME}${COL_RESET}"
    echo "------------------------------------------------------------"
}

main
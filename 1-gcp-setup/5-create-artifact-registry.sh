#!/bin/bash
#
# 5-create-artifact-registry.sh
# Creates a Docker repository in Artifact Registry with cleanup policies.

# --- Strict Mode & Helpers ---
set -euo pipefail

# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Default values
REPO_NAME="gke-apps"
LOCATION="us-central1"
PROJECT_ID=""

# Source config file if it exists
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=config.sh
    source "${CONFIG_FILE}"
fi

COL_INFO="\033[0;34m"
COL_SUCCESS="\033[0;32m"
COL_ERROR="\033[0;31m"
COL_RESET="\033[0m"

log_info()    { echo -e "${COL_INFO}[INFO]${COL_RESET} $1"; }
log_success() { echo -e "${COL_SUCCESS}[SUCCESS]${COL_RESET} $1"; }
log_error()   { echo -e "${COL_ERROR}[ERROR]${COL_RESET} $1"; }

# --- Usage ---
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] 

Creates or updates a Docker repository in Google Artifact Registry. 

OPTIONS:
    -r, --repo NAME        The name of the repository (default: ${REPO_NAME})
    -l, --location REGION  The GCP region for the repository (default: ${LOCATION})
    --project-id ID        GCP project ID (or use config.sh)
    -h, --help             Show this help message
EOF
}



# --- Main Logic ---


main() {


    while [[ $# -gt 0 ]]; do


        case $1 in

            -r|--repo)

                REPO_NAME="$2"

                shift 2

                ;; 

            -l|--location)

                LOCATION="$2"

                shift 2

                ;; 

            --project-id)

                PROJECT_ID="$2"

                shift 2

                ;; 

            -h|--help)

                show_usage

                exit 0

                ;; 

            *)

                log_error "Unknown option: $1"

                show_usage

                exit 1

                ;; 

esac

    done


    # If PROJECT_ID is not set by args or config, get it from gcloud

    if [[ -z "${PROJECT_ID}" ]]; then

        PROJECT_ID=$(command gcloud config get-value project 2>/dev/null)

    fi



    if [[ -z "${PROJECT_ID}" ]]; then

        log_error "Project ID could not be determined. Run 'gcloud config set project [ID]"'

        exit 1

    fi



    log_info "Project: ${PROJECT_ID}, Repo: ${REPO_NAME}, Location: ${LOCATION}"



    # 2. Enable Required APIs

    log_info "Enabling Artifact Registry API..."

    command gcloud services enable artifactregistry.googleapis.com --project="${PROJECT_ID}"



    # 3. Create Repository

    log_info "Checking for Artifact Registry repository '${REPO_NAME}' in ${LOCATION}..."

    if ! command gcloud artifacts repositories describe "${REPO_NAME}" --location="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then

        log_info "Creating repository..."

        command gcloud artifacts repositories create "${REPO_NAME}" \

            --project="${PROJECT_ID}" \

            --repository-format=docker \

            --location="${LOCATION}" \

            --description="Docker repository for GKE apps"

        log_success "Repository created."

    else

        log_info "Repository '${REPO_NAME}' already exists. Skipping creation."

    fi



    # 4. Prepare Cleanup Policy JSON

    log_info "Preparing cleanup policy file..."

    local policy_file

    policy_file=$(mktemp)

    # Using a temporary file is the standard way for this gcloud command

    cat <<EOF > "$policy_file"
[
  {
    "name": "keep-last-five-production",
    "action": {"type": "KEEP"},
    "mostRecentVersions": {
      "keepCount": 5
    },
    "condition": {
       "tagState": "TAGGED",
       "tagPrefixes": ["production"]
    }
  },
  {
    "name": "keep-last-five-staging",
    "action": {"type": "KEEP"},
    "mostRecentVersions": {
      "keepCount": 5
    },
    "condition": {
       "tagState": "TAGGED",
       "tagPrefixes": ["staging"]
    }
  },
  {
    "name": "delete-untagged-after-7-days",
    "action": {"type": "DELETE"},
    "condition": {
      "tagState": "UNTAGGED",
      "olderThan": "604800s"
    }
  }
]
EOF



    # 5. Apply Cleanup Policy

    log_info "Applying cleanup policies..."

    command gcloud artifacts repositories set-cleanup-policies "${REPO_NAME}" \

        --project="${PROJECT_ID}" \

        --location="${LOCATION}" \

        --policy-from-file="$policy_file"



    # Clean up the temp file

    rm -f "$policy_file"



    log_success "Cleanup policies applied successfully."



    # 6. Configure Docker Authentication

    log_info "Configuring Docker authentication for ${LOCATION}-docker.pkg.dev..."

    command gcloud auth configure-docker "${LOCATION}-docker.pkg.dev" --quiet



    echo "------------------------------------------------------------"

    log_success "Artifact Registry Setup Complete!"

    echo -e "Registry URI: ${COL_INFO}${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}${COL_RESET}"

    echo "------------------------------------------------------------"

}



main "$@"

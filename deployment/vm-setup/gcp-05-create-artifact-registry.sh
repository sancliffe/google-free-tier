#!/bin/bash
#
# 5-create-artifact-registry.sh
# Creates a Docker repository in Artifact Registry with cleanup policies.

# --- Strict Mode & Helpers ---
set -euo pipefail

# --- Configuration (with defaults) ---
# Arguments passed from setup-gcp.sh
REPO_NAME="$1"
LOCATION="$2"
PROJECT_ID="$3"

# Source common logging functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
    log_info() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${CYAN}[INFO]${NC} $1"; }
    log_success() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${GREEN}[✅ SUCCESS]${NC} $1"; }
    log_error() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${RED}[ERROR]${NC} $1" >&2; }
fi

# --- Usage ---
show_usage() {
    cat << EOF
Usage: $0 [REPO_NAME] [LOCATION] [PROJECT_ID]

Creates or updates a Docker repository in Google Artifact Registry.

Arguments:
    REPO_NAME        The name of the repository (e.g., gke-apps)
    LOCATION         The GCP region for the repository (e.g., us-central1)
    PROJECT_ID       GCP project ID
EOF
}

# --- Main Logic ---

# Validate inputs
if [[ -z "${REPO_NAME}" || -z "${LOCATION}" || -z "${PROJECT_ID}" ]]; then
    log_error "Missing required arguments."
    show_usage
    exit 1
fi

echo ""
printf '=%.0s' {1..60}; echo
log_info "Artifact Registry Setup"
log_info "Project: ${PROJECT_ID} | Repo: ${REPO_NAME} | Location: ${LOCATION}"
printf '=%.0s' {1..60}; echo
echo ""

# Enable Required APIs
log_info "Enabling Artifact Registry API..."
gcloud services enable artifactregistry.googleapis.com --project="${PROJECT_ID}"

# Create Repository
log_info "Checking for Artifact Registry repository '${REPO_NAME}' in ${LOCATION}..."
if ! gcloud artifacts repositories describe "${REPO_NAME}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
    
    log_info "Creating repository..."
    gcloud artifacts repositories create "${REPO_NAME}" \
        --repository-format=docker \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --description="Docker repository for GKE apps"
    
    log_success "Repository created."
else
    log_info "Repository '${REPO_NAME}' already exists. Skipping creation."
fi

# Prepare Cleanup Policy JSON
# UPDATED: Removed the outer "rules": { ... } wrapper to comply with gcloud requirements.
log_info "Preparing cleanup policy file..."
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" << 'EOF'
[
    {
        "name": "keep-production-tags",
        "action": {
            "type": "KEEP"
        },
        "condition": {
            "tagState": "TAGGED",
            "tagPrefixes": ["production"]
        }
    },
    {
        "name": "keep-staging-tags",
        "action": {
            "type": "KEEP"
        },
        "condition": {
            "tagState": "TAGGED",
            "tagPrefixes": ["staging"]
        }
    },
    {
        "name": "delete-untagged-after-7-days",
        "action": {
        "type": "DELETE"
        },
        "condition": {
        "tagState": "UNTAGGED",
        "olderThan": "604800s"
        }
    }
]
EOF

# Apply Cleanup Policy
log_info "Applying cleanup policies..."
if gcloud artifacts repositories set-cleanup-policies "${REPO_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --policy="${POLICY_FILE}"; then
    log_success "Cleanup policies applied successfully."
else
    log_info "⚠️  Cleanup policies not yet supported in this region or failed to apply."
    log_info "This is OPTIONAL and won't affect repository functionality."
    log_info "You can manually configure cleanup policies in GCP Console > Artifact Registry if needed."
fi

# Clean up the temp file
rm -f "${POLICY_FILE}"

# Configure Docker Authentication
log_info "Configuring Docker authentication for ${LOCATION}-docker.pkg.dev..."
gcloud auth configure-docker "${LOCATION}-docker.pkg.dev" --quiet

echo ""
printf '=%.0s' {1..60}; echo
log_success "Artifact Registry Setup Complete!"
printf '=%.0s' {1..60}; echo
echo ""
log_info "Registry URI:"
log_info "  ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
echo ""
log_info "Next Steps:"
log_info "  1. Build your Docker image:"
echo "     docker build -t ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/my-app:latest ."
log_info "  2. Push to Artifact Registry:"
echo "     docker push ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/my-app:latest"
echo "------------------------------------------------------------"
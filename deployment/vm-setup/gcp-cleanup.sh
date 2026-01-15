#!/bin/bash
# cleanup-gcp-setup.sh
# Removes resources created by scripts 1 through 5 in 1-gcp-setup.

set -euo pipefail

# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Default values
ZONE="us-west1-a"
VM_NAME="free-tier-vm"
FIREWALL_RULE_NAME="allow-http-https"
REPO_NAME="gke-apps"
REPO_LOCATION="us-central1"
PROJECT_ID=""
GCS_BUCKET_NAME="" # Added for GCS cleanup
TF_STATE_BUCKET="" # Added for GCS cleanup

# Flags to control selective deletion
DELETE_VM=false
DELETE_FIREWALL=false
DELETE_MONITORING=false
DELETE_SECRETS=false
DELETE_ARTIFACT_REGISTRY=false
DELETE_GCS_BUCKETS=false # This flag will control both backup and tf state buckets

# Source config file if it exists
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
fi


# --- Usage ---
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deletes the GCP resources created by the setup scripts.

OPTIONS:
    --vm-name NAME         The name of the VM to delete (default: ${VM_NAME})
    --zone ZONE            The GCP zone of the VM (default: ${ZONE})
    --firewall-rule-name NAME The name of the firewall rule to delete (default: ${FIREWALL_RULE_NAME})
    --repo-name NAME       The Artifact Registry repo name (default: ${REPO_NAME})
    --repo-location REGION The repo's GCP region (default: ${REPO_LOCATION})
    --project-id ID        GCP project ID (or use config.sh)
    -h, --help             Show this help message
EOF
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-name)         VM_NAME="$2"; shift 2;;
        --zone)            ZONE="$2"; shift 2;;
        --firewall-rule-name) FIREWALL_RULE_NAME="$2"; shift 2;;
        --repo-name)       REPO_NAME="$2"; shift 2;;
        --repo-location)   REPO_LOCATION="$2"; shift 2;;
        --project-id)      PROJECT_ID="$2"; shift 2;;
        -h|--help)         show_usage; exit 0;;
        *)                 echo "Unknown option: $1"; show_usage; exit 1;;
    esac
done

# Source common logging functions
# shellcheck disable=SC1091
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    # Fallback logging functions if common.sh is not available
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    NC='\033[0m'
    log_info()    { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${CYAN}[INFO]${NC} $*"; }
    log_success() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${GREEN}[✅ SUCCESS]${NC} $*"; }
    log_warn()    { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${YELLOW}[WARN]${NC} $*"; }
    log_error()   { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${RED}[ERROR]${NC} $*" >&2; }
fi

# If PROJECT_ID is not set by args or config, get it from gcloud
if [[ -z "${PROJECT_ID}" ]]; then
    PROJECT_ID=$(gcloud config get-value project)
fi


echo "------------------------------------------------------------"
log_info "Starting Cleanup for Project: ${PROJECT_ID}"
echo "------------------------------------------------------------"
log_warn "This script will PERMANENTLY DELETE the following resources:"
log_warn "  - VM Instance: ${VM_NAME} in ${ZONE}"
log_warn "  - Firewall Rule: ${FIREWALL_RULE_NAME}"
log_warn "  - Monitoring Resources (Uptime Checks, Alert Policies)"
log_warn "  - Secret Manager Secrets"
log_warn "  - Artifact Registry Repo: ${REPO_NAME} in ${REPO_LOCATION}"
echo "------------------------------------------------------------"
read -rp "Are you sure you want to continue? (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" ]]; then
    log_info "Cleanup cancelled."
    exit 0
fi
echo "------------------------------------------------------------"


# 1. Delete VM Instance (from 1-create-vm.sh)
if [[ "${DELETE_VM}" == "true" ]]; then
    log_info "Step 1: Deleting VM instance: ${VM_NAME}..."
    if ! gcloud compute instances delete "${VM_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" --quiet; then
        log_warn "VM ${VM_NAME} not found or already deleted."
    fi
fi

# 2. Delete Firewall Rules (from 2-open-firewall.sh)
if [[ "${DELETE_FIREWALL}" == "true" ]]; then
    log_info "Step 2: Deleting firewall rule: ${FIREWALL_RULE_NAME}..."
    if ! gcloud compute firewall-rules delete "${FIREWALL_RULE_NAME}" --project="${PROJECT_ID}" --quiet; then
        log_warn "Firewall rule ${FIREWALL_RULE_NAME} not found or already deleted."
    fi
fi

# 3. Delete Monitoring Resources (from 3-setup-monitoring.sh)
if [[ "${DELETE_MONITORING}" == "true" ]]; then

# Note: This is not perfectly reliable if you have multiple checks with similar names.
# A more robust solution would store created resource IDs.

# Delete Uptime Checks by display name prefix
UPTIME_CHECKS=$(gcloud monitoring uptime list-configs \
    --project="${PROJECT_ID}" \
    --format='value(name,displayName)' | \
    grep "Uptime check for" | \
    awk '{print $1}' || true)

if [[ -n "${UPTIME_CHECKS}" ]]; then
    for CHECK_FULL_NAME in ${UPTIME_CHECKS}; do
        CHECK_ID=$(basename "${CHECK_FULL_NAME}")
        log_info "Deleting uptime check ${CHECK_ID}..."
        if ! gcloud monitoring uptime delete "${CHECK_ID}" --project="${PROJECT_ID}" --quiet; then
            log_warn "Uptime check ${CHECK_ID} not found or already deleted."
        fi
    done
    log_success "Finished deleting uptime checks."
else
    log_info "No matching uptime checks found to delete."
fi

# Delete Alert Policies by display name prefix
ALERT_POLICIES=$(gcloud alpha monitoring policies list \
    --project="${PROJECT_ID}" \
    --format='value(name,displayName)' | \
    grep "Uptime Check Alert for" | \
    awk '{print $1}' || true)

if [[ -n "${ALERT_POLICIES}" ]]; then
    for POLICY_ID in ${ALERT_POLICIES}; do
        log_info "Deleting alert policy ${POLICY_ID}..."
        if ! gcloud alpha monitoring policies delete "${POLICY_ID}" --project="${PROJECT_ID}" --quiet; then
            log_warn "Alert policy ${POLICY_ID} not found or already deleted."
        fi
    done
    log_success "Finished deleting alert policies."
else
    log_info "No matching alert policies found to delete."
fi
fi

# 4. Delete Secret Manager Secrets (from 4-create-secrets.sh)
if [[ "${DELETE_SECRETS}" == "true" ]]; then
    log_info "Step 4: Deleting secrets..."
    SECRETS=(
        "duckdns_token"
        "email_address"
        "domain_name"
        "gcs_bucket_name"
        "tf_state_bucket"
        "backup_dir"
        "billing_account_id"
    )
    for SECRET in "${SECRETS[@]}"; do
        if gcloud secrets describe "${SECRET}" --project="${PROJECT_ID}" &>/dev/null; then
            if ! gcloud secrets delete "${SECRET}" --project="${PROJECT_ID}" --quiet; then
                log_warn "Secret ${SECRET} could not be deleted."
            else
                log_success "Deleted secret: ${SECRET}"
            fi
        else
            log_info "Secret ${SECRET} not found."
        fi
    done
fi

# 5. Delete Artifact Registry Repository (from 5-create-artifact-registry.sh)
if [[ "${DELETE_ARTIFACT_REGISTRY}" == "true" ]]; then
    log_info "Step 5: Deleting Artifact Registry: ${REPO_NAME}..."
    if gcloud artifacts repositories describe "${REPO_NAME}" --location="${REPO_LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
        if ! gcloud artifacts repositories delete "${REPO_NAME}" \
            --location="${REPO_LOCATION}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            log_warn "Artifact Registry repository ${REPO_NAME} could not be deleted."
        else
            log_success "Deleted repository: ${REPO_NAME}"
        fi
    else
        log_info "Repository ${REPO_NAME} not found."
    fi
fi

# 6. Delete GCS Buckets

if [[ "${DELETE_GCS_BUCKETS}" == "true" ]]; then

    log_info "Step 6: Deleting GCS buckets..."



    # Convert to lowercase to match creation logic

    GCS_BUCKET_NAME_LOWER=$(echo "${GCS_BUCKET_NAME:-}" | tr '[:upper:]' '[:lower:]')

    TF_STATE_BUCKET_LOWER=$(echo "${TF_STATE_BUCKET:-}" | tr '[:upper:]' '[:lower:]')



    if [[ -n "${GCS_BUCKET_NAME_LOWER}" ]] && gsutil ls "gs://${GCS_BUCKET_NAME_LOWER}" &>/dev/null; then

        if ! gsutil rm -r "gs://${GCS_BUCKET_NAME_LOWER}"; then

            log_warn "GCS bucket ${GCS_BUCKET_NAME_LOWER} could not be deleted."

        else

            log_success "Deleted GCS bucket: ${GCS_BUCKET_NAME_LOWER}"

        fi

    else

        log_info "GCS bucket ${GCS_BUCKET_NAME_LOWER} not found or name is empty."

    fi



    if [[ -n "${TF_STATE_BUCKET_LOWER}" ]] && gsutil ls "gs://${TF_STATE_BUCKET_LOWER}" &>/dev/null; then

        if ! gsutil rm -r "gs://${TF_STATE_BUCKET_LOWER}"; then

            log_warn "GCS bucket ${TF_STATE_BUCKET_LOWER} could not be deleted."

        else

            log_success "Deleted GCS bucket: ${TF_STATE_BUCKET_LOWER}"

        fi

    else

        log_info "GCS bucket ${TF_STATE_BUCKET_LOWER} not found or name is empty."

    fi

fi



echo "------------------------------------------------------------"

log_success "Cleanup Process Finished!"

echo "------------------------------------------------------------"

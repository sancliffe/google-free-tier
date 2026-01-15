#!/bin/bash
set -euo pipefail

# --- Configuration (with defaults) ---
# Arguments passed from setup-gcp.sh
VM_NAME="$1"
ZONE="$2"
PROJECT_ID="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    log_info() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${CYAN}[INFO]${NC} $*"; }
    log_success() { echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${GREEN}[✅ SUCCESS]${NC} $*"; }
fi

log_info "Checking if VM '$VM_NAME' already exists in project '$PROJECT_ID' zone '$ZONE'..."

if gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" &>/dev/null; then
  log_info "VM '$VM_NAME' already exists. Exiting."
  exit 0
fi

log_info "VM '$VM_NAME' does not exist. Proceeding with creation."

# 2. Automatically fetch the Project Number for the dynamic Service Account.
#    This service account is created by default for Compute Engine instances.
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# 3. Execute the creation command.
#    - e2-micro is part of Google Cloud's free tier.
#    - debian-12 is a common, stable Linux distribution.
log_info "Creating VM '$VM_NAME'..."
gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=e2-micro \
    --network-interface=network-tier=STANDARD,stack-type=IPV4_ONLY,subnet=default \
    --maintenance-policy=MIGRATE \
    --service-account="$SERVICE_ACCOUNT" \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/pubsub,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
    --create-disk=auto-delete=yes,boot=yes,device-name=persistent-disk-0,image-family=debian-12,image-project=debian-cloud,mode=rw,size=30,type=pd-standard \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring

log_success "VM '$VM_NAME' created successfully."
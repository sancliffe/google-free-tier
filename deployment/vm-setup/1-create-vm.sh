#!/bin/bash
set -euo pipefail

# --- Configuration (with defaults) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arguments passed from setup-gcp.sh
VM_NAME="$1"
ZONE="$2"
PROJECT_ID="$3"

echo "Checking if VM '$VM_NAME' already exists in project '$PROJECT_ID' zone '$ZONE'..."

if gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" &>/dev/null; then
  echo "VM '$VM_NAME' already exists. Exiting."
  exit 0
fi

echo "VM '$VM_NAME' does not exist. Proceeding with creation."

# 2. Automatically fetch the Project Number for the dynamic Service Account.
#    This service account is created by default for Compute Engine instances.
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# 3. Execute the creation command.
#    - e2-micro is part of Google Cloud's free tier.
#    - debian-12 is a common, stable Linux distribution.
echo "Creating VM '$VM_NAME'..."
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

echo "VM '$VM_NAME' created successfully."

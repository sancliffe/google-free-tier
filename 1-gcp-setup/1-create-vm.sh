#!/bin/bash

# 1. Define your Project ID
PROJECT_ID="your-project-id-here"
ZONE="us-west1-a"
VM_NAME="free-tier-vm"

# 2. Automatically fetch the Project Number for the dynamic Service Account
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# 3. Execute the creation command
gcloud compute instances create $VM_NAME \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --network-interface=network-tier=STANDARD,stack-type=IPV4_ONLY,subnet=default \
    --maintenance-policy=MIGRATE \
    --service-account=$SERVICE_ACCOUNT \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/pubsub,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
    --create-disk=auto-delete=yes,boot=yes,device-name=persistent-disk-0,image=projects/debian-cloud/global/licenses/debian-12-bookworm,mode=rw,size=30 \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring

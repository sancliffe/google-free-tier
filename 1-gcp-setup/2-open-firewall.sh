#!/bin/bash

# Define your variables
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-west1-a"
VM_NAME="free-tier-vm"

# Update tags using the variables
gcloud compute instances add-tags $VM_NAME \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --tags=http-server,https-server

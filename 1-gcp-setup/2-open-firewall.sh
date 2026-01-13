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
    
gcloud compute firewall-rules create allow-http \
    --project=$PROJECT_ID \
    --description="Incoming http allowed from anywhere" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server

gcloud compute firewall-rules create allow-https \
    --project=$PROJECT_ID \
    --description="Incoming http allowed from anywhere" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:443 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server

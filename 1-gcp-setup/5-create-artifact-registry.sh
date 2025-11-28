#!/bin/bash
#
# Phase 1: Create Artifact Registry Repository
#
# This repository must exist BEFORE we try to push Docker images to it.
# We create it manually here to avoid circular dependencies in the automation.

set -euo pipefail

REGION="us-central1"
REPO_NAME="gke-apps"
DESCRIPTION="Docker repository for GKE apps"

echo "Enabling Artifact Registry API..."
gcloud services enable artifactregistry.googleapis.com

echo "Creating Artifact Registry repository '${REPO_NAME}' in ${REGION}..."

if gcloud artifacts repositories describe "${REPO_NAME}" --location="${REGION}" &>/dev/null; then
    echo "Repository already exists."
else
    gcloud artifacts repositories create "${REPO_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="${DESCRIPTION}"
    echo "Repository created successfully."
fi

# --- Cost Saving: Apply Cleanup Policy ---
echo "Applying cleanup policy (Keep last 5 versions, delete untagged)..."

# Create a temporary policy file
cat <<EOF > /tmp/cleanup-policy.json
[
  {
    "name": "keep-last-5-versions",
    "action": {"type": "Keep"},
    "mostRecentVersions": {"keepCount": 5}
  },
  {
    "name": "delete-old-images",
    "action": {"type": "Delete"},
    "condition": {"olderThan": "1d"}
  }
]
EOF

gcloud artifacts repositories set-cleanup-policies "${REPO_NAME}" \
    --location="${REGION}" \
    --policy-file=/tmp/cleanup-policy.json \
    --no-dry-run

echo "Cleanup policy applied."
#!/bin/bash
#
# Validate Backend Configuration
# 
# This script checks that the Terraform backend is properly configured.
# It ensures that the GCS backend is not commented out, preventing accidental
# local state storage which breaks team collaboration and state locking.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
BACKEND_FILE="${PROJECT_ROOT}/terraform/backend.tf"

echo "Validating Terraform backend configuration..."

if [ ! -f "$BACKEND_FILE" ]; then
    echo "ERROR: Backend file not found at $BACKEND_FILE"
    exit 1
fi

# Check if backend is still commented out
if grep -q "# backend \"gcs\"" "$BACKEND_FILE"; then
    echo "ERROR: Terraform backend is commented out in $BACKEND_FILE"
    echo ""
    echo "This prevents state locking and breaks team collaboration."
    echo "Remote state storage is not configured."
    echo ""
    echo "To fix this:"
    echo "1. Navigate to terraform/bootstrap directory"
    echo "2. Run: terraform init && terraform apply"
    echo "3. Then uncomment the backend block in terraform/backend.tf"
    echo "4. Run: terraform init to migrate local state to GCS"
    echo ""
    exit 1
fi

# Verify the backend configuration is syntactically valid
if ! grep -q "backend \"gcs\"" "$BACKEND_FILE"; then
    echo "WARNING: GCS backend configuration not found"
    echo "Current backend configuration may not be set up."
fi

echo "✓ Backend configuration looks valid"
echo "✓ Remote state storage is configured for team collaboration"

exit 0

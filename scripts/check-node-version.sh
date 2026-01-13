#!/bin/bash
#
# Check Node.js Version Consistency
#
# This script validates that Node.js version is consistent across all configuration files:
# - app/.nvmrc
# - app/Dockerfile
# - terraform/variables.tf
#
# Inconsistent versions can cause runtime issues and deployment failures.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

NVMRC_FILE="${PROJECT_ROOT}/app/.nvmrc"
DOCKERFILE="${PROJECT_ROOT}/app/Dockerfile"
TF_VARS="${PROJECT_ROOT}/terraform/variables.tf"

echo "Checking Node.js version consistency..."

# Extract versions from each file
if [ ! -f "$NVMRC_FILE" ]; then
    echo "ERROR: .nvmrc file not found at $NVMRC_FILE"
    exit 1
fi

NVMRC_VERSION=$(grep -oE '^[0-9]+' "$NVMRC_FILE" | head -1)
echo "  .nvmrc: $NVMRC_VERSION"

if [ ! -f "$DOCKERFILE" ]; then
    echo "ERROR: Dockerfile not found at $DOCKERFILE"
    exit 1
fi

# Extract NODE_VERSION default from Dockerfile (line with ARG NODE_VERSION)
# Look for ARG NODE_VERSION or FROM node:X-slim patterns
DOCKERFILE_VERSION=$(grep -E "ARG NODE_VERSION|FROM node:[0-9]+" "$DOCKERFILE" | \
    grep -oE "[0-9]+" | head -1)
echo "  Dockerfile: ${DOCKERFILE_VERSION:-not explicitly set}"

if [ ! -f "$TF_VARS" ]; then
    echo "ERROR: terraform/variables.tf not found at $TF_VARS"
    exit 1
fi

# Extract Node.js version from Terraform variables
TF_VERSION=$(grep -A 3 'variable "nodejs_version"' "$TF_VARS" | \
    grep 'default' | grep -oE '"[0-9]+"' | tr -d '"' | head -1)
echo "  terraform/variables.tf: ${TF_VERSION:-not found}"

# Validate consistency
ERRORS=0

if [ -n "$DOCKERFILE_VERSION" ] && [ "$NVMRC_VERSION" != "$DOCKERFILE_VERSION" ]; then
    echo ""
    echo "ERROR: Node.js version mismatch between .nvmrc and Dockerfile"
    echo "  Expected: $NVMRC_VERSION (from .nvmrc)"
    echo "  Got: $DOCKERFILE_VERSION (from Dockerfile)"
    ERRORS=$((ERRORS + 1))
fi

if [ -n "$TF_VERSION" ] && [ "$NVMRC_VERSION" != "$TF_VERSION" ]; then
    echo ""
    echo "ERROR: Node.js version mismatch between .nvmrc and terraform/variables.tf"
    echo "  Expected: $NVMRC_VERSION (from .nvmrc)"
    echo "  Got: $TF_VERSION (from terraform/variables.tf)"
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Version mismatch detected. Please update all files to use the same Node.js version."
    exit 1
fi

echo ""
echo "✓ All Node.js versions are consistent"
exit 0

#!/bin/bash
set -euo pipefail

# This script updates the version number in multiple files
# based on the single source of truth in the VERSION file.

# Ensure we are in the root of the git repository
cd "$(git rev-parse --show-toplevel)"

VERSION_FILE="VERSION"

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: VERSION file not found!"
    exit 1
fi

NEW_VERSION="${1:-}"
CURRENT_VERSION=$(cat "$VERSION_FILE")

if [ -z "$NEW_VERSION" ]; then
    echo "Usage: ./scripts/update-version.sh <new-version>"
    echo "Current version is: $CURRENT_VERSION"
    exit 1
fi

if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in the format X.Y.Z (e.g., 2.1.0)"
    exit 1
fi

echo "Updating version from $CURRENT_VERSION to $NEW_VERSION..."

# 1. Update the VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "✅ Updated VERSION file"

# 2. Update README.md
# This assumes a specific format in the README: "Latest Release: [vX.Y.Z]"
# and a table with version numbers.
if sed -i "s/\\[v${CURRENT_VERSION}\\]/[v${NEW_VERSION}]/g" README.md && \
   sed -i "s/| ${CURRENT_VERSION} /| ${NEW_VERSION} /g" README.md; then
    echo "✅ Updated README.md"
else
    echo "⚠️  Could not find version strings in README.md, skipping."
fi

# 3. Update app/package.json
if [ -f "app/package.json" ]; then
    # Use jq for robust JSON parsing if available
    if command -v jq &> /dev/null; then
        jq ".version = \"$NEW_VERSION\"" app/package.json > app/package.json.tmp && mv app/package.json.tmp app/package.json
        echo "✅ Updated app/package.json (using jq)"
    else
        # Fallback to sed if jq is not installed
        sed -i "s/\"version\": \"${CURRENT_VERSION}\"/\"version\": \"${NEW_VERSION}\"/" app/package.json
        echo "✅ Updated app/package.json (using sed)"
    fi
else
    echo "⚠️  app/package.json not found, skipping."
fi

echo "Version update complete."
echo "Please review the changes and commit them."
#!/bin/bash
echo "Checking prerequisites..."

# Check gcloud
if ! command -v gcloud > /dev/null; then
  echo "❌ gcloud CLI not found"
  exit 1
fi

# Check Docker (for containerized deployments)
if ! command -v docker > /dev/null; then
  echo "⚠️  Docker not found (required for Cloud Run/GKE)"
fi

# Check project is set
if [ -z "$(gcloud config get-value project)" ]; then
  echo "❌ GCP project not set. Run: gcloud config set project PROJECT_ID"
  exit 1
fi

echo "✅ All prerequisites met"
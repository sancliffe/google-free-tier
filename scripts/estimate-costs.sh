#!/bin/bash
set -e

echo "--- Monthly Cost Estimation and Current Usage ---"

echo ""
echo "## Estimated Costs (Free Tier Resources)"
echo "- e2-micro VM: $0 (Always Free)"
echo "- 30GB Storage: $0 (Always Free)"
echo "- Network Egress (>1GB): $0.12/GB"
echo "- Cloud Run (after free tier): Per request, GB-second, egress."
echo "- GKE Autopilot (if enabled): $20-30/month minimum (compute resources are billed)"
echo "- Cloud Functions (after free tier): Per invocation, GB-second, network."
echo ""

read -p "Expected monthly network egress (GB, excluding first 1GB free): " egress
if [[ -n "$egress" && "$egress" =~ ^[0-9]+$ && "$egress" -gt 0 ]]; then
  cost=$(echo "scale=2; $egress * 0.12" | bc)
  echo "Estimated network egress cost: \$$cost"
else
  echo "No additional egress cost estimated (within free tier or input invalid)."
fi
echo ""

echo "## Current Month's Spending (Requires Billing Account ID)"

BILLING_ACCOUNT_ID=""
read -p "Enter your Google Cloud Billing Account ID (e.g., XXXXXX-XXXXXX-XXXXXX), or leave empty to skip: " BILLING_ACCOUNT_ID

if [[ -n "$BILLING_ACCOUNT_ID" ]]; then
  echo "Fetching current month's spending for billing account: $BILLING_ACCOUNT_ID..."
  # Use gcloud beta billing accounts get-spend to get current month's spend.
  # This command typically requires the 'roles/billing.viewer' permission.
  # The output format is not directly parseable as a single number, it provides a summary.
  # For simplicity, we'll just run the command and let the user view the output.
  gcloud beta billing accounts get-spend "$BILLING_ACCOUNT_ID" --format=json || echo "Could not retrieve spending. Ensure you have 'roles/billing.viewer' on the billing account and the ID is correct."
else
  echo "Skipping current month's spending. No billing account ID provided."
fi

echo ""
echo "--- Estimation Complete ---"
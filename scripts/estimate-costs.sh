#!/bin/bash
set -e

# --- WARNING: Incomplete Cost Estimation ---
# This script provides an ESTIMATED cost, primarily for network egress and simplified
# calculations for Cloud Functions, Pub/Sub, and Cloud Logging based on user input.
# It DOES NOT account for:
# - Detailed Cloud Functions resource usage (GB-seconds)
# - Pub/Sub message attributes or other advanced pricing factors
# - Google Cloud Storage operations/egress (beyond free tier)
# - Compute Engine sustained usage discounts
# - Any other GCP services not explicitly listed.
#
# For a comprehensive cost analysis, please refer to the Google Cloud Pricing Calculator
# and your project's billing reports in the GCP Console.
# ---

echo "--- Monthly Cost Estimation and Current Usage ---"

echo ""
echo "## Estimated Costs (Free Tier Resources)"
echo "- e2-micro VM: $0 (Always Free)"
echo "- 30GB Storage: $0 (Always Free)"
echo "- Network Egress (>1GB): $0.12/GB"
echo "- Cloud Run (after free tier): Per request, GB-second, egress (not calculated here)."
echo "- GKE Autopilot (if enabled): $20-30/month minimum (compute resources are billed, not calculated here)."
echo "- Cloud Functions (after free tier): Per invocation, GB-second, network (not calculated here)."
echo ""

read -p "Expected monthly network egress (GB, excluding first 1GB free): " egress
if [[ -n "$egress" && "$egress" =~ ^[0-9]+$ && "$egress" -gt 0 ]]; then
  cost=$(echo "scale=2; $egress * 0.12" | bc)
  echo "Estimated network egress cost: \$$cost"
else
  echo "No additional egress cost estimated (within free tier or input invalid)."
fi
echo ""

# Cloud Functions
echo ""
read -p "Estimated monthly Cloud Functions invocations (beyond 2M free tier): " cf_invocations
if [[ -n "$cf_invocations" && "$cf_invocations" =~ ^[0-9]+$ && "$cf_invocations" -gt 0 ]]; then
  # Pricing example: $0.40 per million invocations
  cf_cost=$(echo "scale=2; $cf_invocations / 1000000 * 0.40" | bc)
  echo "Estimated Cloud Functions invocation cost: \$$cf_cost"
else
  echo "No additional Cloud Functions invocation cost estimated (within free tier or input invalid)."
fi

# Pub/Sub Messages
echo ""
read -p "Estimated monthly Pub/Sub messages (beyond 10GB/month free tier, enter in millions): " ps_messages_million
if [[ -n "$ps_messages_million" && "$ps_messages_million" =~ ^[0-9]+(\.[0-9]+)?$ && $(echo "$ps_messages_million > 0" | bc -l) -eq 1 ]]; then
  # Pricing example: $40 per TB ($0.04 per GB), assume average message size for estimation
  # For simplicity, we'll ask for millions of messages and use a rough estimate of ~1KB per message for 1GB/million messages
  # This is a VERY rough estimate. Real pricing depends on message size.
  ps_cost=$(echo "scale=2; $ps_messages_million * 0.04" | bc) # $0.04 per million messages (assuming 1KB msg avg => 1GB)
  echo "Estimated Pub/Sub message cost: \$$ps_cost (Based on 1KB avg message size and $0.04/GB)"
else
  echo "No additional Pub/Sub message cost estimated (within free tier or input invalid)."
fi

# Cloud Logging
echo ""
read -p "Estimated monthly Cloud Logging volume (GB ingested beyond 50GB free tier): " cl_logging_gb
if [[ -n "$cl_logging_gb" && "$cl_logging_gb" =~ ^[0-9]+(\.[0-9]+)?$ && $(echo "$cl_logging_gb > 0" | bc -l) -eq 1 ]]; then
  # Pricing example: $0.50 per GB ingested
  cl_cost=$(echo "scale=2; $cl_logging_gb * 0.50" | bc)
  echo "Estimated Cloud Logging ingestion cost: \$$cl_cost"
else
  echo "No additional Cloud Logging ingestion cost estimated (within free tier or input invalid)."
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
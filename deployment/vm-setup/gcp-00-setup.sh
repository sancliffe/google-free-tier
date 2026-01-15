#!/bin/bash
# ==============================================================================
# Script: gcp-00-setup.sh
# Description: Orchestrates the setup of the GCP environment.
#              1. Configures GCP project and region.
#              2. Enables required APIs.
#              3. Reserves a static IP.
#              4. Creates a Service Account.
#              5. Creates a GCS bucket for backups.
#              6. Calls gcp-01-create-vm.sh to create the VM.
#              7. Calls gcp-02-firewall-open.sh to configure firewall rules.
#              8. Calls gcp-03-setup-monitoring.sh to setup monitoring (optional).
#              9. Calls gcp-04-create-secrets.sh to create secrets (optional).
#             10. Calls gcp-05-create-artifact-registry.sh to create AR (optional).
#             11. Calls gcp-06-validate.sh to validate the setup.
# Usage: ./gcp-00-setup.sh
# Dependencies: gcloud, common.sh, config.sh
# ==============================================================================

set -euo pipefail

# --- Import Common Functions and Config ---
# Get the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deployment/vm-setup/common.sh
source "${SCRIPT_DIR}/common.sh"

# shellcheck source=deployment/vm-setup/config.sh
source "${SCRIPT_DIR}/config.sh"

# --- Main Execution ---

log_info "Starting GCP environment setup..."

# 1. Configuration (Project, Region, Zone)
log_info "Configuring GCP project settings..."
if [[ -z "${PROJECT_ID}" ]]; then
  error_exit "PROJECT_ID is not set in config.sh"
fi

# Set project
run_command gcloud config set project "${PROJECT_ID}" "Setting GCP project to ${PROJECT_ID}"

# Set compute region and zone (if provided, though region is usually sufficient for some resources)
if [[ -n "${REGION}" ]]; then
  run_command gcloud config set compute/region "${REGION}" "Setting compute region to ${REGION}"
fi
if [[ -n "${ZONE}" ]]; then
  run_command gcloud config set compute/zone "${ZONE}" "Setting compute zone to ${ZONE}"
fi

# 2. Enable Required APIs
log_info "Enabling required GCP APIs..."
REQUIRED_APIS=(
  "compute.googleapis.com"
  "logging.googleapis.com"
  "monitoring.googleapis.com"
  "storage-component.googleapis.com" # For GCS
  "storage-api.googleapis.com"
  "secretmanager.googleapis.com" # If using Secret Manager
  "artifactregistry.googleapis.com" # If using Artifact Registry
)

# Check which APIs are already enabled to avoid unnecessary calls (optimization)
ENABLED_APIS=$(gcloud services list --enabled --format="value(config.name)")

for api in "${REQUIRED_APIS[@]}"; do
  if echo "$ENABLED_APIS" | grep -q "$api"; then
    log_info "API $api is already enabled."
  else
    run_command gcloud services enable "$api" "Enabling API: $api"
  fi
done


# 3. Reserve Static IP
log_info "Reserving static IP address..."
STATIC_IP_NAME="${VM_NAME}-ip"
IP_ADDRESS=""

# Check if IP exists
if gcloud compute addresses describe "$STATIC_IP_NAME" --region="${REGION}" >/dev/null 2>&1; then
  IP_ADDRESS=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="${REGION}" --format="value(address)")
  log_info "Static IP $STATIC_IP_NAME already exists: $IP_ADDRESS"
else
  run_command gcloud compute addresses create "$STATIC_IP_NAME" --region="${REGION}" "Creating static IP $STATIC_IP_NAME"
  IP_ADDRESS=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="${REGION}" --format="value(address)")
  log_info "Created static IP $STATIC_IP_NAME: $IP_ADDRESS"
fi

# Export IP to config (in memory) for subsequent scripts? 
# Actually, create-vm.sh can just look it up by name or we pass it.
# We'll pass it via environment variable or argument if needed, or let create-vm lookup.
# For simplicity, create-vm.sh will look it up using the same name convention or we pass it as an arg.
# Let's verify we have an IP
if [[ -z "$IP_ADDRESS" ]]; then
  error_exit "Failed to obtain static IP address."
fi


# 4. Create Service Account
log_info "Creating Service Account..."
SA_NAME="${SERVICE_ACCOUNT_NAME}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  log_info "Service Account $SA_EMAIL already exists."
else
  run_command gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Service Account for ${VM_NAME}" \
    "Creating Service Account $SA_NAME"
fi

# Grant necessary permissions to the Service Account
# Minimum roles: Logging, Monitoring, Storage Object Admin (for backups)
log_info "Granting roles to Service Account..."
ROLES=(
  "roles/logging.logWriter"
  "roles/monitoring.metricWriter"
  "roles/monitoring.viewer"
  "roles/storage.objectAdmin" # Read/Write to GCS buckets
  "roles/secretmanager.secretAccessor" # If fetching secrets
  "roles/artifactregistry.reader" # If pulling images
)

for role in "${ROLES[@]}"; do
    # Check if policy binding already exists to avoid cluttering logs/errors? 
    # add-iam-policy-binding is idempotent but prints a lot.
    run_command gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="$role" \
      "Granting $role to $SA_EMAIL" >/dev/null
done


# 5. Create GCS Bucket for Backups
log_info "Creating GCS bucket for backups..."
BUCKET_NAME=$(echo "${GCS_BUCKET_NAME}" | tr '[:upper:]' '[:lower:]')

if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  log_info "GCS Bucket gs://${BUCKET_NAME} already exists."
else
  # Create bucket (standard storage, regional)
  run_command gsutil mb -p "${PROJECT_ID}" -c standard -l "${REGION}" -b on "gs://${BUCKET_NAME}" "Creating GCS Bucket gs://${BUCKET_NAME}"
  # Enable versioning (recommended for backups)
  run_command gsutil versioning set on "gs://${BUCKET_NAME}" "Enabling versioning on gs://${BUCKET_NAME}"
  
  # Lifecycle rule: Delete objects older than 30 days (example)
  # Create a temporary lifecycle json
  cat > lifecycle.json <<EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 30}
    }
  ]
}
EOF
  run_command gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}" "Setting lifecycle rule on gs://${BUCKET_NAME}"
  rm -f lifecycle.json
fi


# 6. Call Sub-scripts

# 6.1 Create VM
log_info "=== Step 6.1: Creating VM ==="
"${SCRIPT_DIR}/gcp-01-create-vm.sh" "${VM_NAME}" "${ZONE}" "${PROJECT_ID}"

# 6.2 Configure Firewall
log_info "=== Step 6.2: Configuring Firewall ==="
"${SCRIPT_DIR}/gcp-02-firewall-open.sh" "${VM_NAME}" "${ZONE}" "${FIREWALL_RULE_NAME}" "${PROJECT_ID}" "${TAGS}"

# 6.3 Monitoring (Optional)
if [[ "${ENABLE_MONITORING}" == "true" ]]; then
  log_info "=== Step 6.3: Setting up Monitoring ==="
  "${SCRIPT_DIR}/gcp-03-setup-monitoring.sh" "${VM_NAME}" "${ZONE}" "${EMAIL_ADDRESS}" "${DISPLAY_NAME}" "${DOMAIN}" "${PROJECT_ID}"
else
  log_info "Skipping Monitoring setup (ENABLE_MONITORING != true)"
fi

# 6.4 Secrets (Optional)
if [[ "${USE_SECRET_MANAGER}" == "true" ]]; then
    log_info "=== Step 6.4: Creating Secrets ==="
    "${SCRIPT_DIR}/gcp-04-create-secrets.sh" \
        --duckdns-token "${DUCKDNS_TOKEN}" \
        --email "${EMAIL_ADDRESS}" \
        --domain "${DOMAIN}" \
        --bucket "${GCS_BUCKET_NAME}" \
        --tf-state-bucket "${TF_STATE_BUCKET}" \
        --backup-dir "${BACKUP_DIR}" \
        --billing-account "${BILLING_ACCOUNT_ID}" \
        --project-id "${PROJECT_ID}"
else
    log_info "Skipping Secret Manager setup (USE_SECRET_MANAGER != true)"
fi

# 6.5 Artifact Registry (Optional)
# If you plan to deploy containers
log_info "=== Step 6.5: Creating Artifact Registry ==="
"${SCRIPT_DIR}/gcp-05-create-artifact-registry.sh" "${REPO_NAME}" "${REPO_LOCATION}" "${PROJECT_ID}"


# --- Post-Creation Setup on the VM ---
# This part is crucial. We have created the infrastructure.
# Now we need to provision the software *inside* the VM.
# We can use `gcloud compute ssh` to execute the host setup scripts.

log_info "Waiting for VM to be ready for SSH..."
# Simple loop to wait for SSH
for i in {1..20}; do
  if gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="echo SSH Ready" >/dev/null 2>&1; then
    log_info "VM is SSH accessible."
    break
  fi
  log_info "Waiting for SSH... ($i/20)"
  sleep 10
done

log_info "=== Uploading setup scripts to VM ==="
# We copy the entire current directory (deployment/vm-setup) to the VM
# so it has access to all scripts and config.
# Excluding common.sh and config.sh because they are needed, wait, we need everything.
# We'll copy to a 'setup' directory in the home folder.

# Use scp to copy files
# Note: --recurse is for gcloud compute scp
run_command gcloud compute scp --recurse "${SCRIPT_DIR}" "${VM_NAME}:/tmp/vm-setup" --zone="${ZONE}" "Uploading setup scripts to VM"

log_info "=== Executing Host Setup Scripts on VM ==="

# We need to construct a command that runs the scripts in order.
# We also need to ensure environment variables from config.sh are available, 
# or rely on config.sh being present on the VM (which we just uploaded).
# Since we uploaded the whole folder, the scripts on the VM can source config.sh relative to themselves.

# However, config.sh might rely on local env vars if they were not hardcoded?
# In this design, config.sh contains the values. If config.sh uses `export VAR=${VAR:-default}`, 
# we need to ensure the values are set.
# If the user edited config.sh locally, those values are in the file we uploaded. 
# So sourcing config.sh on the VM should work, PROVIDED config.sh doesn't rely on 
# environment variables from the *host* machine (the one running this script) that aren't in the file.

# Let's look at how we run the remote script.
# We'll make the scripts executable and run host-00-setup.sh which acts as a master script or run them individually.
# Looking at the file list, there isn't a master 'host-all' script, but host-00-setup.sh seems like a good start or we run them sequentially here.
# Wait, host-00-setup.sh is "setup".
# Let's iterate through the host scripts.

HOST_SCRIPTS=(
  "host-00-setup.sh"
  "host-01-create-swap.sh"
  "host-02-setup-duckdns.sh"
  "host-03-firewall-config.sh"
  "host-04-install-nginx.sh"
  "host-05-setup-ssl.sh"
  "host-06-setup-security.sh"
  "host-07-setup-backups.sh"
  "host-08-test-backup-restore.sh" # Optional, maybe manual? Included for now.
  "host-09-setup-ops-agent.sh"
  "host-cleanup.sh"
)

# Prepare the remote command execution
# We want to run this in a non-interactive shell.
# We need to make sure 'config.sh' variables are respected.
# The scripts source common.sh and config.sh.

# Issue: DUCKDNS_TOKEN might be sensitive and not in config.sh if passed via ENV.
# If config.sh has `DUCKDNS_TOKEN=${DUCKDNS_TOKEN:-""}`, and we run on VM, it will be empty unless we export it.

# We will construct a block of exports for variables that might be sensitive or dynamic.
# Explicitly passing critical config vars as environment variables to the remote SSH command.

# Variables to pass explicitly
VM_ENV_VARS=(
  "DUCKDNS_TOKEN=${DUCKDNS_TOKEN}"
  "GCS_BUCKET_NAME=${GCS_BUCKET_NAME}"
)

# Build the setup command
# We use a heredoc to define the remote script execution for cleanliness
# BUT passing env vars to gcloud ssh command property is tricky. 
# Best way: Prepend exports to the command string.

ENV_SETUP_COMMAND=""
for var_entry in "${VM_ENV_VARS[@]}"; do
  # Split key and value
  KEY="${var_entry%%=*}"
  VALUE="${var_entry#*=}"
  # Escape value for shell safety (basic)
  # This simple escaping might not handle all edge cases but suffices for typical tokens
  ESCAPED_VALUE=$(printf '%q' "$VALUE")
  # Append to command string. We export them and also append to .bashrc for persistence if needed
  # (though usually only needed for the session).
  # Persistence is useful for cron jobs or future sessions.
  ENV_SETUP_COMMAND+="export $KEY=$ESCAPED_VALUE; "
  # Optional: Persist to .bashrc on VM (be careful with secrets)
  # ENV_SETUP_COMMAND+="echo 'export $KEY=$ESCAPED_VALUE' >> ~/.bashrc; "
done

# Fix for ShellCheck errors SC1078, SC1079:
# Ensure quotes are properly closed and variable expansion is safe.
# We will use a simpler approach for the remote command to avoid complex nested quoting hell.
# We will write a temporary runner script on the remote machine.

log_info "Generating remote runner script..."

# Create a temporary runner script locally
cat > runner.sh <<EOF
#!/bin/bash
set -e
cd /tmp/vm-setup

# Fix DOS line endings if present, which can cause silent script failures
sed -i 's/\r$//' *.sh

# Export sensitive variables passed from local machine
export DUCKDNS_TOKEN="${DUCKDNS_TOKEN}"
export GCS_BUCKET_NAME="${GCS_BUCKET_NAME}"
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"

# Make scripts executable
chmod +x *.sh

# Execute scripts in order
EOF

for script in "${HOST_SCRIPTS[@]}"; do
  echo "./$script" >> runner.sh
done

# Upload the runner
run_command gcloud compute scp runner.sh "${VM_NAME}:/tmp/vm-setup/runner.sh" --zone="${ZONE}" "Uploading runner script"
rm -f runner.sh

# Execute the runner
log_info "Executing runner script on VM..."
run_command gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="chmod +x /tmp/vm-setup/runner.sh && sudo /tmp/vm-setup/runner.sh" "Running host setup scripts"

# 7. Validation
log_info "=== Step 7: Final Validation ==="
"${SCRIPT_DIR}/gcp-06-validate.sh"

log_info "GCP Environment Setup Complete!"
echo ""
echo "You can SSH into your VM using:"
echo "gcloud compute ssh ${VM_NAME} --zone=${ZONE}"
echo ""
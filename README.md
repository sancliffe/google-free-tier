# google-free-tier

**A complete guide to hosting applications on Google Cloud Platform's Free Tier.**

Setup and configure a web server on a Google Cloud Free Tier `e2-micro` VM, or deploy containerized applications using Cloud Run and GKE Autopilot—all within free tier limits!

**New in v2.0:** The containerized applications now feature a persistent **Visitor Counter** backed by **Google Cloud Firestore**, demonstrating stateful serverless deployments!



## Deployment Options

Choose your preferred deployment path:

| Path | Technologies | Best For | Cost |
|------|---------------|----------|------|
| **Manual VM Setup** (Phases 1-2) | Bash, Nginx, DuckDNS, Let's Encrypt | Learning, hobby projects | Free |
| **Serverless Cloud Run** (Phase 3) | Node.js, Docker, Firestore | Scalable web apps | Free* |
| **Kubernetes (GKE Autopilot)** (Phase 4) | Kubernetes, GKE, Firestore | Production workloads | ~$20-30/mo |
| **Infrastructure as Code** (Phase 5) | Terraform, Packer, CI/CD | Reproducible infrastructure | Varies |

*Cloud Run free tier: 2M requests, 360,000 GB-seconds per month

---

## Documentation

This project includes comprehensive documentation:

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - How to contribute to this project
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** - Community guidelines and expectations
- **[SECURITY.md](SECURITY.md)** - Security best practices and vulnerability reporting
- **[RELEASING.md](RELEASING.md)** - Release process and versioning guidelines

---

## Prerequisites

Before starting, ensure you have the following installed on your **local machine**:

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud`) - authenticated with your GCP account
- [Docker](https://docs.docker.com/get-docker/) - for containerized deployments (Phases 3-5)
- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) - for Infrastructure as Code (Phase 5)
- Git - to clone this repository
- Active GCP account with billing enabled (required even for free tier resources)

**Important:** Even though this guide focuses on free tier resources, you must have billing enabled on your GCP project. Set up billing alerts to avoid unexpected charges.

---

## Cost Considerations

**Free Tier Resources:**
- **Compute Engine:** 1 `e2-micro` VM instance (744 hours/month in select regions)
- **Persistent Disk:** 30GB standard persistent disk storage
- **Cloud Run:** 2 million requests/month, 360,000 GB-seconds/month
- **Firestore:** 1GB storage, 50,000 reads/day, 20,000 writes/day
- **Cloud Build:** 120 build-minutes/day
- **Cloud Monitoring:** First 150 MB of logs per month

**Resources That May Incur Costs:**
- **GKE Autopilot:** While there's no cluster management fee, you pay for the compute resources (vCPU/RAM) your pods use (~$20-30/month for a basic deployment)
- **Cloud Storage:** Storage beyond 5GB per month
- **Network Egress:** 
**NETWORK EGRESS WARNING:**
- Free tier: 1GB/month from North America only (excluding China/Australia)
- Premium tier egress is charged
- **Static external IPs on stopped VMs incur charges (~$3/month)**
- Consider using standard tier networking for cost savings
- **Cloud Functions:** Invocations beyond free tier limits (used by the Cost Killer function)
- **External IP Addresses:** While an external IP for a running `e2-micro` VM is often free, a static external IP address *retained* for a *stopped* VM instance will incur charges. **Always release unused static external IP addresses to prevent unexpected costs.**

**Cost Optimization Tips:**
- Enable billing alerts and budgets in GCP Console (covered in Phase 1, Step 3)
- Review [GCP Free Tier documentation](https://cloud.google.com/free/docs/free-cloud-features)
- Use the included Cost Killer function (Phase 5) to prevent overages
- Destroy resources when not in use to avoid unexpected charges
- Monitor your usage regularly via Cloud Console

---

## Security & Contributing

This project is committed to being a welcoming and safe community for all contributors. Before getting started:

1. **Read our [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** - Community standards and expectations
2. **Review [SECURITY.md](SECURITY.md)** - Security best practices and how to report vulnerabilities
3. **Check [CONTRIBUTING.md](CONTRIBUTING.md)** - How to contribute improvements and fixes

**For maintainers:** See [RELEASING.md](RELEASING.md) for our release process.

---

## Quick Start

Ready to get started? Here's the 30-second setup:

```bash
# 1. Clone the repository
git clone https://github.com/BranchingBad/google-free-tier.git
cd google-free-tier

# 2. Make setup scripts executable
chmod +x 1-gcp-setup/setup-gcp.sh 2-host-setup/*.sh 3-cloud-run-deployment/*.sh 3-gke-deployment/*.sh

# 3. Choose your path:
# - Manual: Start with Phase 1 below
# - Cloud Run: Jump to Phase 3 after Phase 1
# - Kubernetes: Jump to Phase 4 after Phase 1
- Full IaC: Jump to Phase 5 after Phase 1

### Before You Begin

Run the prerequisites check:
```bash
bash scripts/check-prerequisites.sh
```

This verifies:
- gcloud CLI is installed and authenticated
- Required APIs are enabled
- Billing is active
- Necessary permissions are granted
```

## Pre-Terraform Checklist
- [ ] Run `bash scripts/validate-backend.sh` before any terraform command
- [ ] Ensure `backend "gcs"` block is uncommented in `backend.tf`
- [ ] Verify state bucket exists: `gsutil ls gs://PROJECT_ID-tfstate`

**Estimated Time:** 
- Manual VM setup: 30-45 minutes
- Cloud Run deployment: 15-20 minutes (after Phase 1)
- GKE deployment: 20-30 minutes (after Phase 1)
- Full Terraform: 10-15 minutes (after Phase 1)

---

## Phase 1: Google Cloud Setup (Automated)

This phase prepares your GCP environment by creating a VM, setting up firewall rules, monitoring, secrets, and an artifact registry. The process is automated with a single script.

### 1. Configure Your Setup

Before running the script, you need to create a configuration file.

```bash
cd 1-gcp-setup
cp config.sh.example config.sh
```

Now, edit `config.sh` and fill in the required values for your environment.

### 2. Run the Setup Script

Once the configuration is ready, run the automated setup script from the `1-gcp-setup` directory:

```bash
bash ./setup-gcp.sh
```
This script will:
- Create the `e2-micro` VM instance.
- Open firewall ports for HTTP and HTTPS traffic.
- Set up monitoring and alerting for your VM.
- Create secrets in Google Secret Manager.
- Create a Docker repository in Artifact Registry.

The script is idempotent, meaning you can safely run it multiple times. After running the script, you can proceed to Phase 2.



## Phase 2: Host VM Setup (Manual)

SSH into your VM and run these scripts from the `2-host-setup/` directory.

```bash
gcloud compute ssh free-tier-vm --zone=us-central1-a
```

Once connected, clone this repository on the VM:
```bash
git clone https://github.com/BranchingBad/google-free-tier.git
cd google-free-tier

# Make scripts executable
chmod +x 2-host-setup/*.sh
```

The scripts in `2-host-setup/` are numbered for clarity. Run them in order. They are idempotent (can be safely re-run).

### 1. Create Swap File 

Creates a 2GB swap file to support the 1GB RAM limit of the e2-micro.

```bash
sudo bash ./2-host-setup/1-create-swap.sh
```

**Validation:** Check swap is active:
```bash
free -h
swapon --show
```

### 2. Install Nginx 

Installs and enables the web server.

```bash
sudo bash ./2-host-setup/2-install-nginx.sh
```

**Validation:** Visit your VM's external IP in a browser:
```bash
curl http://$(curl -s ifconfig.me)
```

### 3. Setup DuckDNS 

Configures a cron job to keep your dynamic DNS updated.

```bash
bash ./2-host-setup/3-setup-duckdns.sh
```

Or provide arguments to skip prompts:
```bash
bash ./2-host-setup/3-setup-duckdns.sh "your-subdomain" "your-duckdns-token"
```

**Validation:** Check the cron job:
```bash
crontab -l | grep duckdns
```

### 4. Setup SSL 

Installs Let's Encrypt SSL certificates using Certbot.

```bash
sudo bash ./2-host-setup/4-setup-ssl.sh
```

Or with arguments:
```bash
sudo bash ./2-host-setup/4-setup-ssl.sh "your-domain.duckdns.org" "your-email@example.com"
```

**Important:** Ensure your domain is pointing to your server before running this script. The script performs a DNS pre-flight check.

**Validation:** Test SSL certificate:
```bash
curl https://your-domain.duckdns.org
```

### 5. Adjust Local Firewall 

Configures `ufw` to allow Nginx traffic (if active).

```bash
sudo bash ./2-host-setup/5-adjust-firewall.sh
```

This script automatically checks if `ufw` is active before making changes.

### 6. Setup Automated Backups 

Configures a daily cron job to back up your site to Google Cloud Storage.

```bash
# Interactive mode
sudo bash ./2-host-setup/6-setup-backups.sh

# With arguments
sudo bash ./2-host-setup/6-setup-backups.sh "your-backup-bucket-name" "/var/www/html"
```

**Note:** You must create the GCS bucket first:
```bash
gsutil mb gs://your-backup-bucket-name
```

**Validation:** Check the backup cron job:
```bash
sudo crontab -l | grep backup
```

### Test Backup Restoration (Recommended Quarterly)

It is crucial to regularly test your backup restoration process to ensure data integrity and a smooth recovery in case of a disaster.

```bash
# First, you need to get the latest backup file from your GCS bucket.
# Replace BUCKET with your actual GCS backup bucket name.
# You can find the exact backup filename by listing the bucket:
# gsutil ls gs://YOUR_BACKUP_BUCKET/

# Set your values
YOUR_BACKUP_BUCKET="your-backup-bucket-name" # Replace with your actual GCS backup bucket name

# Example: Copy the latest backup (adjust filename as needed)
gsutil cp gs://"${YOUR_BACKUP_BUCKET}"/backup-YYYY-MM-DD-HHMMSS.tar.gz /tmp/

# Create a temporary directory to restore into
mkdir -p /tmp/restore-test/

# Extract the backup
tar -xzf /tmp/backup-YYYY-MM-DD-HHMMSS.tar.gz -C /tmp/restore-test/

# Verify contents (e.g., list files, check important data)
ls -la /tmp/restore-test/your-backup-directory-name/

# Clean up temporary files
rm /tmp/backup-YYYY-MM-DD-HHMMSS.tar.gz
rm -r /tmp/restore-test/
```

### 7. Harden Security 

Installs Fail2Ban and configures unattended security updates.

```bash
sudo bash ./2-host-setup/7-setup-security.sh
```

**Validation:** Check Fail2Ban status:
```bash
sudo fail2ban-client status
```

### 8. Install Ops Agent 

Installs the Google Cloud Ops Agent to monitor Memory and Swap usage (metrics not available by default).

```bash
sudo bash ./2-host-setup/8-setup-ops-agent.sh
```

This enables enhanced monitoring in Cloud Console for memory and swap metrics.

**Validation:** Check agent status:
```bash
sudo systemctl status google-cloud-ops-agent
```

---

## Phase 3: Cloud Run Deployment (Serverless)

Deploy a Node.js application to Google Cloud Run (Free Tier eligible). The updated app now connects to Firestore to persist a visitor count.

### Prerequisites
- Docker installed on your local machine
- Artifact Registry created (Phase 1, Step 5)
- **Firestore Database (REQUIRED):** Cloud Run and GKE applications require a Firestore database for the visitor counter feature.
  
  **Important:** Firestore is NOT created by default. You have two options:
  
  **Option 1: Automatic Creation (Recommended)**
  - Set `enable_firestore_database = true` in your `terraform.tfvars` before running Terraform
  - Terraform will create the database during initial `terraform apply`
  
  **Option 2: Manual Creation**
  - Skip Terraform creation (default: `enable_firestore_database = false`)
  - Manually create in GCP Console: Firestore > Create Database > Native Mode > Select region
  - Ensure you set the location to match your other resources
  
  **Verify your setup:**
  ```bash
  gcloud firestore databases list
  ```
  
  If no database is listed or the app crashes with "No default database found", see [Troubleshooting - Firestore Errors](#12-firestore-errors).

### Deploy to Cloud Run
```bash
# From your local machine (in the repository root)
bash ./3-cloud-run-deployment/setup-cloud-run.sh
```

This script will:

Configure Docker authentication with Artifact Registry

Prompt you to build the Docker container image

Prompt you to push it to Google Artifact Registry

Deploy the service to Cloud Run with unauthenticated access

**Features Enabled:**

Firestore Integration: The app increments a counter in the visits collection in your default database.

Static Assets: The app links to a public asset in Google Cloud Storage.

**Validation:** Once complete, get the URL of your service:

```bash
gcloud run services describe hello-cloud-run --region=us-central1 --format='value(status.url)'
```

Visit the URL in your browser to see your application running and the visitor count incrementing!

---

## Phase 4: GKE Autopilot Deployment (Kubernetes)

## **CRITICAL COST WARNING FOR GKE**

**GKE Autopilot is NOT FREE**. You will incur charges of approximately **$20-30/month** even with a single pod using minimal resources.

| Cost Component | Monthly Cost |
|----------------|--------------|
| vCPU (250m) | ~$15 |
| Memory (512Mi) | ~$10 |
| **Total** | **~$25/month** |

This is NOT covered by the free tier. Proceed only if you understand these costs.

Deploy the same Firestore-connected Node.js application to GKE Autopilot.

### Prerequisites
- Docker installed
- Artifact Registry created (Phase 1, Step 5)
- Terraform installed (the script uses Terraform for cluster provisioning)
- Firestore Database: Created in Phase 1, Step 6.

### Deploy to GKE

```bash
# From your local machine (in the repository root)
bash ./3-gke-deployment/setup-gke.sh
```

This script will:
1. Configure Docker authentication
2. Prompt you to build and push the Docker image
3. Fetch configuration from Secret Manager
4. Use Terraform to provision the GKE Autopilot cluster
5. Apply Kubernetes manifests to deploy your application

**Validation:** Check your deployment:
```bash
# Set your values
REGION="us-central1" # Your cluster region

# Configure kubectl
gcloud container clusters get-credentials gke-autopilot-cluster --region="${REGION}"

# Check pods and services
kubectl get pods
kubectl get services
kubectl get ingress
```

**Get the public IP:**
```bash
kubectl get ingress hello-gke-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Cleanup:** To avoid ongoing charges, destroy the GKE resources:
```bash
# Set your values
ENABLE_GKE="true"
ENABLE_VM="false"
ENABLE_CLOUD_RUN="false"

cd terraform
terraform destroy -var="enable_gke=${ENABLE_GKE}" -var="enable_vm=${ENABLE_VM}" -var="enable_cloud_run=${ENABLE_CLOUD_RUN}"
```

Or destroy everything managed by Terraform:
```bash
terraform destroy
```

---

## Phase 5: Terraform (Infrastructure as Code)

The terraform/ directory automates the creation of all infrastructure including VM, GKE cluster, Cloud Run services, monitoring, and "Cost Killer" logic. It also handles the enabling of Firestore APIs and IAM permissions required for the new application features.

### Prerequisites
- Terraform installed on your local machine
- Google Cloud SDK authenticated
- All secrets created (Phase 1, Step 4)

### 1. Bootstrap State Bucket

Before running the main Terraform configuration, create a GCS bucket to store Terraform state.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Enter your GCP project ID when prompted. This creates a versioned GCS bucket named `<project-id>-tfstate` for storing Terraform state files securely.

### 2. Configure Variables

Create a `terraform/terraform.tfvars` file in the main `terraform/` directory:

```hcl
project_id              = "your-gcp-project-id"
region                  = "us-central1"
zone                    = "us-central1-a"
artifact_registry_region = "us-central1"
email_address           = "your-email@example.com"
duckdns_token           = "your-duckdns-token"
domain_name             = "your-domain.duckdns.org"
gcs_bucket_name         = "your-backup-bucket"
backup_dir              = "/var/www/html"
tf_state_bucket         = "your-project-id-tfstate"  # Created in step 1
billing_account_id      = "XXXXXX-XXXXXX-XXXXXX"     # Your billing account ID
image_tag               = "latest"

# Feature Flags - Enable/disable components
enable_vm                       = true   # Deploy the e2-micro VM
enable_cloud_run                = true   # Deploy Cloud Run service
enable_cloud_run_domain_mapping = false  # Map custom domain to Cloud Run (conflicts with VM on same domain)
enable_firestore_database       = true   # Enable Firestore database creation (set to false if created manually)
enable_gke                      = false  # Deploy GKE cluster (costs $20-30/month)

# Budget Configuration
budget_amount = "5"  # Monthly budget in USD
cost_killer_shutdown_threshold = 1.0 # Shutdown VM at 100% of budget
```

**Security Note:** Never commit `terraform.tfvars` to version control. It's already in `.gitignore`.

### 3. Initialize Terraform

Navigate to the `terraform/` directory and initialize with your state bucket:

```bash
# Set your values
TF_STATE_BUCKET="your-project-id-tfstate" # The GCS bucket for your Terraform state

cd terraform
terraform init -backend-config="bucket=${TF_STATE_BUCKET}"
```

Replace `your-project-id-tfstate` with the bucket created in step 1.

### 4. Plan and Apply

Review the execution plan:
```bash
terraform plan
```

If everything looks correct, apply the changes:
```bash
terraform apply
```

Type `yes` when prompted to create the resources.

### 5. Verify Deployment

After Terraform completes:

```bash
# Check VM (if enabled)
gcloud compute instances list

# Check Cloud Run (if enabled)
gcloud run services list

# Check GKE (if enabled)
gcloud container clusters list

# View outputs
terraform output
```

### Cost Killer Function

The Terraform configuration includes a "Cost Killer" Cloud Function (`terraform/budget.tf`).

**How it works:**
- Monitors your GCP billing via Pub/Sub notifications
- Triggers when budget threshold is reached (default: 50%, 90%, 100%)
- At a configurable threshold (default: 100%), automatically stops the VM to prevent overages
- Sends email notification via the configured alert channel

**Configuration:**
```hcl
# In terraform/terraform.tfvars
budget_amount = "5"  # Monthly budget in USD (default: $5)
cost_killer_shutdown_threshold = 1.0 # Shutdown VM at 100% of budget
```

**Limitations:**
- Only stops the VM instance
- Does NOT stop Cloud Run or GKE services
- You must manually disable those services if costs exceed expectations

**Testing:**
```bash
# Check function logs
gcloud functions logs read cost-killer --limit=50

# Check budget status
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID
```

### Destroy Resources

To tear down all Terraform-managed resources:

```bash
cd terraform
terraform destroy
```

**Warning:** This will delete all resources including VMs, clusters, and may cause data loss. Ensure you have backups.

To destroy only the state bucket:
```bash
cd bootstrap
terraform destroy
```

---

## Cleanup / Teardown

### Manual Setup Cleanup (Phases 1-2)

```bash
# Set your values
ZONE="us-central1-a" # Your VM zone

# Delete the VM
gcloud compute instances delete free-tier-vm --zone="${ZONE}"

# Delete monitoring uptime checks
gcloud monitoring uptime-checks list
gcloud monitoring uptime-checks delete UPTIME_CHECK_ID

# Delete alert policies
gcloud alpha monitoring policies list
gcloud alpha monitoring policies delete POLICY_ID

# Delete notification channels
gcloud alpha monitoring channels list
gcloud alpha monitoring channels delete CHANNEL_ID

# Delete secrets
gcloud secrets delete duckdns_token
gcloud secrets delete email_address
gcloud secrets delete domain_name
gcloud secrets delete gcs_bucket_name
gcloud secrets delete tf_state_bucket
gcloud secrets delete backup_dir
gcloud secrets delete billing_account_id

# Delete artifact registry (repository name is 'gke-apps')
gcloud artifacts repositories delete gke-apps --location=us-central1

# CRITICAL: Backup Firestore before deletion
gcloud firestore export gs://YOUR_BACKUP_BUCKET/firestore-backup-$(date +%Y%m%d)

# Delete Firestore database (WARNING: Permanent!)
gcloud firestore databases delete --database='(default)'

# Delete backup bucket (will delete all backups!)
gsutil rm -r gs://your-backup-bucket-name

# Delete firewall rules (if you want to clean up completely)
gcloud compute firewall-rules delete allow-http-https
gcloud compute firewall-rules delete allow-ssh-from-iap
```

### Cloud Run Cleanup (Phase 3)

```bash
# Delete the service
gcloud run services delete hello-cloud-run --region=us-central1

# Delete container images
gcloud artifacts docker images list us-central1-docker.pkg.dev/PROJECT_ID/gke-apps
gcloud artifacts docker images delete \
  us-central1-docker.pkg.dev/PROJECT_ID/gke-apps/hello-cloud-run:latest
```

### GKE Cleanup (Phase 4)

If you deployed GKE using Terraform (via the main terraform directory):

```bash
cd terraform
terraform destroy
```

Or to destroy only GKE resources while keeping VM:

```bash
# Set your values
ENABLE_GKE="true"
ENABLE_VM="false"

cd terraform
terraform destroy -var="enable_gke=${ENABLE_GKE}" -var="enable_vm=${ENABLE_VM}"
```

Or delete the cluster manually:

```bash
# Set your values
REGION="us-central1" # Your cluster region

gcloud container clusters delete gke-autopilot-cluster --region="${REGION}"
```

### Terraform Cleanup (Phase 5)

```bash
# Destroy all infrastructure
cd terraform
terraform destroy

# Optionally delete the state bucket
cd bootstrap
terraform destroy
```

---

## Advanced: Packer & CI/CD

### Packer

Located in `packer/`, this configuration builds a custom Google Compute Engine image with Nginx, Swap, and security settings pre-installed.

**Benefits:**
- Faster VM provisioning
- Consistent server configuration
- Immutable infrastructure

**Build the image:**
```bash
cd packer
packer init .
packer build -var="project_id=YOUR_PROJECT_ID" gce-image.pkr.hcl
```

**Use the custom image:**

Update the `image_family` variable in your Terraform configuration or VM creation command:

```bash
gcloud compute instances create free-tier-vm \
  --image=gcp-free-tier-nginx-TIMESTAMP \
  --image-project=your-project-id \
  --machine-type=e2-micro \
  --zone=us-central1-a
```

### Cloud Build (CI/CD)

The `cloudbuild.yaml` file defines an automated pipeline:

1. **Lint** - Validates shell scripts with shellcheck
2. **Validate** - Checks Terraform syntax
3. **Build** - Creates Docker images for Cloud Run and GKE
4. **Deploy** - Applies Terraform changes automatically

#### Docker Image Build Process

The Docker image, defined in `app/Dockerfile`, is built with a strong focus on security, reproducibility, and minimal size. Key features of the build process include:

-   **Node.js Version Consistency:** Currently, the Node.js version is specified in `app/.nvmrc` (e.g., `20`), used in `Dockerfile` (e.g., `FROM node:20-slim`), and in Terraform Cloud Function `runtime` (e.g., `"nodejs20"`). For better consistency and easier management, consider creating a shared variable file to define the Node.js version across all configurations.
-   **Slim Base Image**: Uses `node:20-slim` as the base to reduce the image size and potential attack surface.
-   **Reproducible Builds**: `npm ci --only=production` is used to install dependencies, ensuring that the exact versions from `package-lock.json` are used every time.
-   **Non-Root User**: The application is run as a non-root `node` user to limit the container's privileges and enhance security.
-   **Proper Process Management**: `dumb-init` is used as the entrypoint to correctly handle signals and reap orphaned child processes, preventing zombie processes.
-   **Automated Tagging**: In the Cloud Build pipeline, the Docker image is automatically tagged with the short git commit SHA (`_SHORT_SHA`), ensuring that every deployment is traceable to a specific version of the code.

**Setup Cloud Build trigger:**

```bash
# Connect your GitHub repository
gcloud builds triggers create github \
  --repo-name=google-free-tier \
  --repo-owner=YOUR_GITHUB_USERNAME \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml
```

**Grant Cloud Build necessary permissions:**

```bash
# Get Cloud Build service account email
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)")
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# Grant permissions
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/container.admin"

gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/iam.serviceAccountUser"
```

Now every push to the `main` branch will trigger the pipeline.

### Pre-commit Hooks

To help maintain code quality and prevent common issues, a pre-commit hook is provided in the `.git-hooks/` directory. This hook includes checks for:
- Potential secrets in staged changes (e.g., using `trufflehog` or similar).
- Shell script syntax validation (e.g., using `shellcheck`).
- Terraform formatting (e.g., `terraform fmt -check`).

To enable this hook in your local repository, copy or symlink it to your `.git/hooks/` directory and make it executable:
```bash
mkdir -p .git/hooks/
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Alternatively, you can configure Git to use the `.git-hooks` directory directly:
```bash
git config core.hooksPath .git-hooks
```
Note: If you use `core.hooksPath`, ensure the scripts inside `.git-hooks` are executable (`chmod +x .git-hooks/*`).

---

## Troubleshooting

### Quick Reference

| Issue | Solution | Docs |
|-------|----------|------|
| SSH connection fails | Check firewall rules and IAP configuration | [Security.md](SECURITY.md#access-control) |
| Domain doesn't resolve | Wait 5-10 min for DNS propagation, then try again | Phase 2, Step 3 |
| SSL certificate fails | Ensure domain resolves before running script | Phase 2, Step 4 |
| Firestore errors | Create default Firestore database in Console | Phase 3 Prerequisites |
| Out of memory errors | Verify swap file is active: `free -h` | Phase 2, Step 1 |
| Nginx won't start | Check if port 80/443 in use: `sudo lsof -i :80` | Phase 2, Step 2 |
| Docker auth fails | Re-run: `gcloud auth configure-docker` | Phase 3 |
| Terraform locked | Run: `terraform force-unlock LOCK_ID` | Phase 5 |

---

### Common Terraform Errors

**Error: "Error creating Instance: googleapi: Error 403: Compute Engine API has not been used"**
- Solution: `gcloud services enable compute.googleapis.com`

**Error: "Backend configuration changed"**
- Solution: `terraform init -reconfigure`

**Error: "Resource already exists"**
- Solution: `terraform import google_compute_instance.default PROJECT/ZONE/INSTANCE_NAME`

### Common Issues

**1. DNS Propagation Delays**
- **Problem:** SSL certificate fails because domain doesn't resolve
- **Solution:** Wait 5-10 minutes after setting up DuckDNS before running SSL script
- **Check:** `nslookup your-domain.duckdns.org`

**2. Firestore Errors**
- **Problem:** App crashes with "Error: No default database found", "Permission denied", or "Quota exceeded" errors.
- **Solution:**
  - **"Database not found"**:
    - Ensure Firestore database was created. Terraform *does not* create this by default; you must either create it manually in Native mode or set `enable_firestore_database = true` in your `terraform.tfvars`.
    - Check: `gcloud firestore databases list`
  - **"Permission denied"**:
    - Ensure the service account running your application (e.g., Cloud Run, GKE pod) has the `Cloud Datastore User` role (`roles/datastore.user`) on the project.
    - Check service account IAM bindings in GCP Console.
  - **"Quota exceeded"**:
    - Review your Firestore usage in the GCP Console.
    - Check for sudden spikes in reads/writes.
    - Consider upgrading your Firestore billing plan or optimizing database operations.

**3. Insufficient Permissions**
- **Problem:** `gcloud` commands fail with permission errors
- **Solution:** Ensure you have necessary IAM roles (Compute Admin, Storage Admin, etc.)
- **Check:** `gcloud projects get-iam-policy PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:user:YOUR_EMAIL"`

**4. Swap File Not Activating**
- **Problem:** System still runs out of memory
- **Solution:** Verify swap is enabled: `sudo swapon -a` and check `free -h`
- **Debug:** Check logs: `journalctl -u swap.target`

**5. Port 80/443 Already in Use**
- **Problem:** Nginx fails to start
- **Solution:** Check what's using the ports: `sudo lsof -i :80` and kill the process
- **Alternative:** `sudo netstat -tulpn | grep :80`

**6. Docker Permission Denied**
- **Problem:** Cannot connect to Docker daemon
- **Solution:** Add user to docker group: `sudo usermod -aG docker $USER` then logout/login
- **Quick fix:** Use `sudo` before docker commands

**7. Terraform State Locked**
- **Problem:** `terraform apply` fails with state lock error
- **Solution:** If you're sure no other process is running: `terraform force-unlock LOCK_ID`
- **Prevention:** Always use `terraform destroy` to clean up, never manually delete resources

**8. Cost Killer Not Triggering**
- **Problem:** Billing exceeded but VM still running
- **Solution:** Check Cloud Function logs, verify Pub/Sub subscription, ensure IAM permissions
- **Debug:** 
  ```bash
  gcloud functions logs read cost-killer --limit=50
  gcloud pubsub subscriptions list
  ```

**9. Artifact Registry Authentication Fails**
- **Problem:** `docker push` fails with authentication error
- **Solution:** Re-run: `gcloud auth configure-docker us-central1-docker.pkg.dev`
- **Alternative:** Use `gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://us-central1-docker.pkg.dev`

**10. Terraform Backend Initialization Error**
- **Problem:** `terraform init` fails to find backend bucket
- **Solution:** Ensure you created the state bucket in bootstrap step and use correct bucket name
- **Check:** `gsutil ls | grep tfstate`

**11. GKE Cluster Connection Failed**
- **Problem:** `kubectl` commands fail after cluster creation
- **Solution:** Get credentials: `gcloud container clusters get-credentials CLUSTER_NAME --region=us-central1`

**12. Firestore Errors**
- **Problem:** App crashes with "Error: No default database found", "Permission denied", or "Quota exceeded" errors.
- **Solution:**
  - **"Database not found" or "No default database found"**:
    - Firestore is NOT created automatically. You must explicitly enable it.
    - Check if a database exists: `gcloud firestore databases list`
    - **If no database exists:**
      - Option A: Set `enable_firestore_database = true` in `terraform.tfvars`, then run `terraform apply`
      - Option B: Create manually in GCP Console: Firestore > Create Database > Native Mode > Select appropriate region
      - Ensure the database is in the same region as your other resources
    - Restart your application after creating the database (Cloud Run: redeploy, GKE: restart pod)
  - **"Permission denied"**:
    - The service account running your application lacks Firestore permissions
    - Ensure the service account has the `roles/datastore.user` role (Cloud Datastore User)
    - For Cloud Run: Check the compute service account permissions in IAM Console
    - For GKE: Verify the Workload Identity service account has required permissions
    - To grant permissions:
      ```bash
      # Example for Cloud Run (replace PROJECT_ID)
      gcloud projects add-iam-policy-binding PROJECT_ID \
        --member=serviceAccount:YOUR_SERVICE_ACCOUNT@appspot.gserviceaccount.com \
        --role=roles/datastore.user
      ```
  - **"Quota exceeded"**:
    - You've exceeded Firestore's free tier limits (1GB storage, 50,000 reads/day, 20,000 writes/day)
    - Review your Firestore usage in GCP Console: Firestore > Usage tab
    - Check for sudden spikes in reads/writes (possible infinite loops or high traffic)
    - Solutions:
      - Optimize database queries to reduce unnecessary reads
      - Add caching to reduce repeated reads
      - Consider upgrading to paid plan if expected traffic exceeds free tier
      - Set up budget alerts to monitor costs

### Getting Help

- Check [GCP Documentation](https://cloud.google.com/docs)
- Open an issue on [GitHub](https://github.com/BranchingBad/google-free-tier/issues)
- Review logs:
  - VM: `journalctl -u nginx` or `gcloud logging read`
  - Cloud Run: `gcloud run services logs read hello-cloud-run`
  - GKE: `kubectl logs POD_NAME`

---

## Security Best Practices

1. **Never commit secrets to Git**
   - Add `terraform.tfvars`, `*.env`, and `*.key` to `.gitignore` (already done)
   - Use Secret Manager for all sensitive data
   - Rotate credentials regularly

2. **Use least-privilege IAM roles**
   - Don't use Owner role for service accounts
   - Grant only necessary permissions
   - Review permissions quarterly

3. **Enable OS Login**
   ```bash
   # Set your values
   ZONE="us-central1-a"
   
   gcloud compute instances add-metadata free-tier-vm \
     --metadata enable-oslogin=TRUE \
     --zone="${ZONE}"   ```

4. **Regular security updates**
   - The security script enables unattended-upgrades
   - Check regularly: `sudo apt update && sudo apt upgrade`
   - Monitor CVE announcements

5. **Monitor access logs**
   - Review Fail2Ban logs: `sudo fail2ban-client status sshd`
   - Check Nginx access logs: `sudo tail -f /var/log/nginx/access.log`
   - Set up log-based alerts in Cloud Monitoring

6. **Use strong firewall rules**
   - Only open necessary ports
   - Consider restricting SSH to specific IPs
   - Use IAP for SSH access (included in Terraform config)
   - For public web access, consider additional layers of protection:
     - Google Cloud Armor for WAF and DDoS protection
     - Implement Nginx rate limiting (see Nginx documentation)
     - Utilize a CDN/proxy like Cloudflare in front of the VM

7. **Secure Terraform State Bucket**
   - Apply strict IAM restrictions to your Terraform state bucket (e.g., `roles/storage.objectViewer` for read-only access, `roles/storage.objectAdmin` for write access to specific users/service accounts).
   - Ensure only authorized personnel or automation can access state files.

8. **Enable 2FA on your GCP account**
   - Go to https://myaccount.google.com/security
   - Enable 2-Step Verification
   - Use security keys for additional protection

9. **Audit Trail**
   - Enable Cloud Audit Logs
   - Review activity regularly
   - Set up anomaly detection alerts

---

## Contributing

We welcome contributions! Whether you're fixing bugs, improving documentation, adding features, or helping other users, your help is appreciated.

**To contribute:**

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes following [Conventional Commits](https://www.conventionalcommits.org/): 
   ```bash
   git commit -m 'feat: Add amazing feature'
   ```
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

**Before contributing, please:**
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines
- Review [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Ensure shell scripts pass `shellcheck`: `shellcheck *.sh`
- Test your changes in a clean GCP project
- Update documentation as needed

---

## Getting Help

### Documentation
- **Setup Help:** Review the appropriate phase section below
- **Security Questions:** See [SECURITY.md](SECURITY.md)
- **Contributing:** See [CONTRIBUTING.md](CONTRIBUTING.md)

### Community Support
- **Issues & Bugs:** [GitHub Issues](https://github.com/BranchingBad/google-free-tier/issues)
- **Questions & Discussions:** [GitHub Discussions](https://github.com/BranchingBad/google-free-tier/discussions)
- **Report Security Issues:** See [SECURITY.md](SECURITY.md) for responsible disclosure

### Debugging
Check the [Troubleshooting](#-troubleshooting) section below for solutions to common problems.

---

## Acknowledgments

- **Google Cloud Platform** - For the generous free tier
- **Let's Encrypt** - For free SSL certificates
- **DuckDNS** - For free dynamic DNS services
- **Open Source Community** - For Nginx, Terraform, Kubernetes, and the tools that power this project
- **Our Contributors** - Thank you for improving this project!

---

## License

This project is open source and available under the [MIT License](LICENSE).

---

## Project Status

| Component | Status | Version |
|-----------|--------|---------|
| Manual VM Setup | Stable | 2.0.0 |
| Cloud Run | Stable | 2.0.0 |
| GKE Autopilot | Stable | 2.0.0 |
| Terraform | Stable | 2.0.0 |
| Bash Utilities | Stable | 2.0.0 |
| Documentation | Complete | 2.0.0 |

---

## Additional Resources

### Official Documentation
- [Google Cloud Free Tier](https://cloud.google.com/free)
- [Google Cloud Console](https://console.cloud.google.com)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [GKE Autopilot Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview)

### Tools & Technologies
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Certbot Documentation](https://certbot.eff.org/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform Documentation](https://www.terraform.io/docs)

### Learning Resources
- [Google Cloud Quickstarts](https://cloud.google.com/docs/quickstarts)
- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices.html)
- [Infrastructure as Code Guide](https://en.wikipedia.org/wiki/Infrastructure_as_code)

---

**Last Updated:** November 29, 2025  
**Latest Release:** [v2.0.0](https://github.com/BranchingBad/google-free-tier/releases/tag/v2.0.0)

---

## Architecture Diagram (Suggested)

This project would benefit from a visual architecture diagram, illustrating the relationships between:
- The VM with Nginx
- Cloud Storage for backups
- Cloud Monitoring/Alerting
- The Cost Killer function
- Firestore integration

---

## License

This project is open source and available under the [MIT License](LICENSE).

# ☁️ google-free-tier

Setup and configure a web server on a Google Cloud Free Tier `e2-micro` VM, or deploy containerized applications using Cloud Run and GKE Autopilot.

This project offers multiple paths for deployment:
- **Manual Setup (Phases 1-2):** Step-by-step shell scripts to configure a VM.
- **Serverless (Phase 3):** Deploy a container to Cloud Run.
- **Kubernetes (Phase 4):** Deploy a container to GKE Autopilot.
- **Terraform (Phase 5):** Fully automated Infrastructure-as-Code provisioning.

---

## Phase 1: 🏗️ Google Cloud Setup (Manual)

Run these commands from your **local machine** to prepare your GCP environment.

### 1. Create the VM Instance 💻

Creates an `e2-micro` instance running Debian 12.

```bash
# See 1-gcp-setup/1-create-vm.txt for the full command
gcloud compute instances create free-tier-vm \
  --machine-type=e2-micro \
  --zone=us-central1-a \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=30GB \
  --boot-disk-type=pd-standard \
  --boot-disk-auto-delete
```

### 2. Open Firewall Ports 🔥

Allows HTTP and HTTPS traffic to the VM.

```bash
# See 1-gcp-setup/2-open-firewall.txt
gcloud compute instances add-tags free-tier-vm \
  --tags=http-server,https-server \
  --zone=us-central1-a
```

### 3. Setup Monitoring and Alerting 📊

Sets up an uptime check and email alerts if your site goes down.

```bash
bash ./1-gcp-setup/3-setup-monitoring.sh
```

### 4. Create Secrets 🤫

Interactively creates secrets (DuckDNS token, Email, etc.) in Google Secret Manager.

```bash
bash ./1-gcp-setup/4-create-secrets.sh
```

### 5. Create Artifact Registry 🐳

Creates the Docker repository required for Cloud Run and GKE deployments.

```bash
bash ./1-gcp-setup/5-create-artifact-registry.sh
```

---

## Phase 2: ⚙️ Host VM Setup (Manual)

SSH into your VM (`gcloud compute ssh free-tier-vm`) and run these scripts from the `2-host-setup/` directory.

### 1. Create Swap File 💾

Creates a 2GB swap file to support the 1GB RAM limit of the e2-micro.

```bash
sudo bash ./2-host-setup/1-create-swap.sh
```

### 2. Install Nginx 🌐

Installs and enables the web server.

```bash
sudo bash ./2-host-setup/2-install-nginx.sh
```

### 3. Setup DuckDNS 🦆

Configures a cron job to keep your dynamic DNS updated.

```bash
bash ./2-host-setup/3-setup-duckdns.sh
```

### 4. Setup SSL 🔒

Installs Let's Encrypt SSL certificates using Certbot.

```bash
sudo bash ./2-host-setup/4-setup-ssl.sh
```

### 5. Adjust Local Firewall 🛡️

Configures `ufw` to allow Nginx traffic (if active).

```bash
sudo bash ./2-host-setup/5-adjust-firewall.sh
```

### 6. Setup Automated Backups 📦

Configures a daily cron job to back up your site to Google Cloud Storage.

```bash
sudo bash ./2-host-setup/6-setup-backups.sh
```

### 7. Harden Security 🛡️

Installs Fail2Ban and configures unattended security updates.

```bash
sudo bash ./2-host-setup/7-setup-security.sh
```

### 8. Install Ops Agent 📈

Installs the Google Cloud Ops Agent to monitor Memory and Swap usage (metrics not available by default).

```bash
sudo bash ./2-host-setup/8-setup-ops-agent.sh
```

---

## Phase 3: 🚀 Cloud Run Deployment (Serverless)

Deploy a Node.js application to **Google Cloud Run** (Free Tier eligible).

```bash
# From your local machine
bash ./3-cloud-run-deployment/setup-cloud-run.sh
```

- Builds and pushes the Docker image to Artifact Registry.
- Deploys the service to Cloud Run.

---

## Phase 4: ☸️ GKE Autopilot Deployment (Kubernetes)

Deploy a Node.js application to **GKE Autopilot**.

**Note:** While GKE Autopilot eliminates the cluster management fee, the compute resources (vCPU/RAM) used by your pods are billed.

```bash
# From your local machine
bash ./3-gke-deployment/setup-gke.sh
```

- Builds and pushes the Docker image.
- Uses **Terraform** to provision the GKE cluster and apply Kubernetes manifests.

---

## Phase 5: 🤖 Terraform (Infrastructure as Code)

The `terraform/` directory automates the creation of the VM, GKE cluster, Cloud Run services, and "Cost Killer" logic.

### 1. Bootstrap State Bucket

Before running the main Terraform, you must create the remote state bucket.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

### 2. Configure Variables

Create a `terraform/terraform.tfvars` file:

```hcl
project_id      = "your-project-id"
email_address   = "your-email@example.com"
duckdns_token   = "your-token"
domain_name     = "your-domain.duckdns.org"
gcs_bucket_name = "your-backup-bucket"
tf_state_bucket = "your-tf-state-bucket" # Created in step 1

# Feature Flags
enable_vm        = true
enable_cloud_run = true
enable_gke       = false # Set to true to deploy GKE
```

### 3. Deploy

```bash
cd terraform
terraform init -backend-config="bucket=YOUR_STATE_BUCKET_NAME"
terraform apply
```

### 💸 Cost Killer Function

The Terraform configuration includes a "Cost Killer" Cloud Function (`terraform/budget.tf`). If your billing exceeds the budget (default $5), this function automatically attempts to stop the VM to prevent overages.

---

## Advanced: 📦 Packer & CI/CD

### Packer

Located in `packer/`, this configuration builds a custom Google Compute Engine image with Nginx, Swap, and security settings pre-installed, speeding up VM provisioning.

### Cloud Build (CI/CD)

The `cloudbuild.yaml` file defines a pipeline that:

1. Lints shell scripts.
2. Validates Terraform code.
3. Builds and pushes Docker images for Cloud Run and GKE.
4. Applies Terraform changes automatically.

---

## 📝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 💬 Support

If you encounter any issues or have questions, please open an issue on the GitHub repository.
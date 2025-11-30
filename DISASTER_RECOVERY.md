# 🚨 Disaster Recovery Plan

This document outlines the procedures to recover the application and its data in the event of a disaster. A disaster is any event that renders the primary infrastructure unusable, such as a regional GCP outage, catastrophic data corruption, or accidental deletion of critical resources.

## 1. Recovery Objectives

- **Recovery Time Objective (RTO):** 4 hours. This is the target time within which the service must be restored after a disaster to avoid unacceptable consequences associated with a break in business continuity.
- **Recovery Point Objective (RPO):** 24 hours. This is the maximum acceptable amount of data loss, measured in time. As backups are daily, we can lose up to 24 hours of data.

## 2. Emergency Contact Information

| Role                | Name           | Email                     | Phone          |
| ------------------- | -------------- | ------------------------- | -------------- |
| **Primary On-Call** | [Name Here]    | [email@example.com]       | [Phone Number] |
| **Secondary On-Call**| [Name Here]    | [email@example.com]       | [Phone Number] |
| **GCP Support**     | [Account Rep]  | [gcp-support@example.com] | [Phone Number] |

## 3. Recovery Procedures

This plan assumes a total loss of the primary GCP region (`us-central1`). Recovery will involve provisioning new infrastructure in a secondary region (e.g., `us-west1`).

### Step 1: Initial Assessment (0-30 mins)

1.  **Declare a Disaster:** The Primary On-Call engineer declares a disaster after confirming the outage is not a transient issue (e.g., by checking the [GCP Status Dashboard](https://status.cloud.google.com/)).
2.  **Notify Stakeholders:** Inform all relevant parties via the established emergency communication channels.
3.  **Access Credentials:** Ensure you have access to:
    *   GCP Console with appropriate IAM permissions.
    *   Terraform Cloud or the GCS bucket containing the Terraform state.
    *   The `google-free-tier` Git repository.

### Step 2: Infrastructure Recreation (30 mins - 2 hours)

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/BranchingBad/google-free-tier.git
    cd google-free-tier
    ```

2.  **Configure Terraform for the New Region:**
    *   Create a `terraform/terraform.tfvars` file.
    *   Set the `region` and `zone` variables to the new recovery region (e.g., `region = "us-west1"`).
    *   Ensure all other variables (`project_id`, `billing_account_id`, etc.) are correct.

3.  **Initialize and Apply Terraform:**
    ```bash
    cd terraform
    # Initialize with the existing state bucket
    terraform init -backend-config="bucket=your-tf-state-bucket"
    
    # Apply the configuration to the new region
    terraform apply -auto-approve
    ```
    This will provision a new VM, GCS buckets, and all other configured infrastructure in the new region.

### Step 3: Data Restoration (2 - 3 hours)

1.  **Identify the Latest Backup:**
    *   Access the GCS backup bucket (`gs://your-backup-bucket-name`).
    *   Identify the most recent backup file (e.g., `backup-YYYY-MM-DD-HHMMSS.tar.gz`).

2.  **Restore Data to the New VM:**
    *   SSH into the newly created VM:
        ```bash
        gcloud compute ssh free-tier-vm --zone=your-new-zone
        ```
    *   On the VM, download and extract the backup:
        ```bash
        # Create a temporary directory
        mkdir /tmp/restore
        
        # Copy the backup from GCS
        gsutil cp gs://your-backup-bucket-name/LATEST_BACKUP.tar.gz /tmp/restore/
        
        # Extract the archive to the correct location (e.g., /var/www/html)
        # Ensure the destination directory exists and is empty
        sudo tar -xzf /tmp/restore/LATEST_BACKUP.tar.gz -C /
        ```

3.  **Restore Firestore Data (if applicable):**
    *   If Firestore data needs to be restored from a GCS export, use the `gcloud firestore import` command.

### Step 4: DNS Failover (3 - 4 hours)

1.  **Update DNS Records:**
    *   Log in to your DNS provider (e.g., DuckDNS).
    *   Update the A record for your domain (`your-domain.duckdns.org`) to point to the new VM's external IP address.
    *   The external IP can be found in the GCP Console or by running `gcloud compute instances describe new-vm-name`.

2.  **Re-issue SSL Certificate:**
    *   Once DNS has propagated (can take minutes to hours), SSH into the new VM.
    *   Run the SSL setup script to obtain a new certificate for the domain:
        ```bash
        sudo bash /path/to/2-host-setup/4-setup-ssl.sh
        ```

### Step 5: Validation (4 hours onwards)

1.  **Verify Application Functionality:**
    *   Access the application via its domain.
    -   Check that all core features are working.
    *   Verify that the restored data is correct.
2.  **Monitor Logs and Metrics:**
    *   Check Cloud Monitoring for any unusual errors or performance issues.
3.  **Declare All-Clear:** Once confident the system is stable, the Primary On-Call can declare the disaster recovery complete.

## 4. Testing Schedule

-   **Full DR Test (Quarterly):** A full-scale test of this entire plan should be conducted once per quarter. This involves failing over to a secondary region and then failing back.
-   **Backup Restoration Test (Weekly):** The automated backup script includes a weekly test to ensure backup integrity, but a manual test should also be performed monthly.

---
This is a template and should be adapted to the specific needs of your application.

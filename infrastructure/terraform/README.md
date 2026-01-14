# Terraform for Google Free Tier Project

This directory contains a Terraform project to deploy the resources from the `google-free-tier` project.

## Prerequisites

1.  **Google Cloud Project:** You need to have a Google Cloud project with billing enabled.
2.  **gcloud CLI:** You need to have the `gcloud` CLI installed and configured to use your project.
3.  **Terraform:** You need to have Terraform installed locally.

## Setup

The setup is a two-step process to handle the initial creation of the Terraform state bucket, separating its lifecycle from the main infrastructure.

### 1. Bootstrap the Terraform State Bucket

First, we will create the GCS bucket that will be used to store the Terraform state.

1.  **Navigate to the bootstrap directory:**
    ```bash
    cd terraform/bootstrap
    ```

2.  **Initialize Terraform:**
    This will download the necessary providers and initialize the backend locally.
    ```bash
    terraform init
    ```

3.  **Apply the configuration:**
    This will create the GCS bucket. You will be prompted to enter your GCP `project_id`.
    ```bash
    terraform apply
    ```
    Once this is complete, you will have a GCS bucket named `<project_id>-tfstate`.

### 2. Deploy the Main Infrastructure

Now that the state bucket exists, you can configure the main Terraform project to use it as a backend.

1.  **Navigate back to the main terraform directory:**
    ```bash
    cd ..
    ```

2.  **Configure the backend:**
    - Open the `backend.tf` file.
    - Uncomment the `backend "gcs"` block.
    - Replace `<YOUR_PROJECT_ID>` with your actual GCP project ID.

3.  **Initialize Terraform:**
    This command will configure the backend, downloading provider plugins and pointing Terraform to your newly created GCS state bucket.
    ```bash
    terraform init -reconfigure
    ```

4.  **Create a `terraform.tfvars` file:**
    Create a file named `terraform.tfvars` in the `terraform` directory and add the following variables. This file should **not** be committed to your repository.
    ```hcl
    project_id      = "your-gcp-project-id"
    duckdns_token   = "your-duckdns-token"
    email_address   = "your-email@example.com"
    domain_name     = "your.duckdns.org"
    gcs_bucket_name = "your-backup-bucket"
    backup_dir      = "/var/www/html"
    ```

5.  **Apply the configuration:**
    Deploy the main infrastructure.
    ```bash
    terraform apply
    ```

## Manual Terraform Commands

You can use other Terraform commands locally for inspection:
```bash
# See what changes Terraform will make
terraform plan

# See the current output values
terraform output
```

## Outputs

The Terraform configuration will output the following values:
*   `instance_name`: The name of the GCE instance.
*   `instance_public_ip`: The public IP address of the GCE instance.
*   `gke_cluster_name`: The name of the GKE cluster.
*   `kubernetes_service_ip`: The public IP address of the Kubernetes service.
*   `region`: The GCP region where resources are deployed.

You can get these values by running `terraform output`.

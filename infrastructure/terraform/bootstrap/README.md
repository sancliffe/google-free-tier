# Terraform State Bootstrap

This directory contains the Terraform configuration to create the GCS bucket used to store the Terraform state for the main infrastructure.

## Usage

1. **Navigate to this directory:**
   ```bash
   cd terraform/bootstrap
   ```

2. **Initialize Terraform:**
   This will download the necessary providers and initialize the backend locally.
   ```bash
   terraform init
   ```

3. **Apply the configuration:**
   This will create the GCS bucket. You will be prompted to enter your GCP `project_id`.
   ```bash
   terraform apply
   ```

Once this is complete, you will have a GCS bucket named `<project_id>-tfstate`. This bucket will be used to store the state of your main infrastructure.

## Cleanup Warning
The Terraform state bucket has `prevent_destroy = true`. 
To delete it:
1. Remove lifecycle block from `bootstrap/main.tf`
2. Run `terraform destroy` in bootstrap directory
3. Manually delete bucket: `gsutil rm -r gs://PROJECT_ID-tfstate`
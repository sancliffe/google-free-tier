terraform {
  # backend "gcs" {
  #   bucket = "<YOUR_PROJECT_ID>-tfstate"
  #   prefix = "terraform/state"
  # }
}

# 1. Create the GCS bucket for the Terraform state by running the bootstrap configuration:
#    cd bootstrap
#    terraform init
#    terraform apply
#
# 2. Uncomment the backend configuration above.
#
# 3. Replace <YOUR_PROJECT_ID> with your GCP project ID.
#
# 4. Initialize Terraform:
#    terraform init -reconfigure
#
# 5. Apply the main configuration:
#    terraform apply

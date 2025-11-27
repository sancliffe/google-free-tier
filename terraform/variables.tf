# This file will contain the input variables for the Terraform project.
variable "duckdns_token" {
  description = "The DuckDNS token."
  type        = string
  sensitive   = true
}

variable "email_address" {
  description = "The email address for SSL certificate renewal notices."
  type        = string
}

variable "domain_name" {
  description = "The domain name (e.g., my.duckdns.org)."
  type        = string
}

variable "gcs_bucket_name" {
  description = "The name of the GCS bucket for backups."
  type        = string
}

variable "image_tag" {
  description = "The tag for the Docker image."
  type        = string
  default     = "latest"
}

variable "tf_state_bucket" {
  description = "The name of the GCS bucket to store the Terraform state. This must be globally unique."
  type        = string
}

variable "backup_dir" {
  description = "The absolute path of the directory to back up."
  type        = string
}

variable "project_id" {
  description = "The ID of the GCP project."
  type        = string
}

# --- Updated Defaults for Region Alignment ---

variable "region" {
  description = "The region to deploy the resources in."
  type        = string
  # CHANGED: Default to us-central1 to match Cloud Build and GKE Free Tier eligibility
  default     = "us-central1"
}

variable "zone" {
  description = "The zone to deploy the resources in."
  type        = string
  # CHANGED: Default to a zone within us-central1
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "The machine type for the VM."
  type        = string
  default     = "e2-micro"
}

variable "image_family" {
  description = "The image family for the VM."
  type        = string
  default     = "debian-12"
}

variable "image_project" {
  description = "The image project for the VM."
  type        = string
  default     = "debian-cloud"
}

variable "boot_disk_size" {
  description = "The size of the boot disk in GB."
  type        = number
  default     = 30
}

variable "boot_disk_type" {
  description = "The type of the boot disk."
  type        = string
  default     = "pd-standard"
}
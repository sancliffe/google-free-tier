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

variable "backup_dir" {
  description = "The absolute path of the directory to back up."
  type        = string
}

variable "project_id" {
  description = "The ID of the GCP project."
  type        = string
}

# --- UPDATE: Added Billing Account ID ---
variable "billing_account_id" {
  description = "The alphanumeric ID of the billing account (e.g., XXXXXX-XXXXXX-XXXXXX)."
  type        = string
  sensitive   = true
}

# --- Feature Flags ---

variable "enable_vm" {
  description = "Enable the Compute Engine VM (Standard Free Tier)."
  type        = bool
  default     = true
}

variable "enable_cloud_run" {
  description = "Enable the Cloud Run service (Modern Free Tier)."
  type        = bool
  default     = true
}

variable "enable_cloud_run_domain_mapping" {
  description = "Map the custom domain to Cloud Run. WARNING: Causes conflict if VM is also enabled with the same domain."
  type        = bool
  default     = false
}

variable "enable_gke" {
  description = "Enable the GKE cluster (WARNING: Incurs compute costs)."
  type        = bool
  default     = false
}

# --- Region & Machine Config ---

variable "region" {
  description = "The region to deploy the resources in."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The zone to deploy the resources in."
  type        = string
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
variable "duckdns_token" {
  description = "The DuckDNS token."
  type        = string
  sensitive   = true
}

variable "email_address" {
  description = "The email address for SSL certificate renewal notices."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.email_address))
    error_message = "Must be a valid email address."
  }
}

variable "domain_name" {
  description = "The domain name (e.g., my.duckdns.org)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid FQDN."
  }
}

variable "gcs_bucket_name" {
  description = "The name of the GCS bucket for backups."
  type        = string

  validation {
    # GCS bucket naming rules: https://cloud.google.com/storage/docs/naming-buckets
    # - Must be 3-63 characters
    # - Can contain only lowercase letters, numbers, hyphens, underscores, and dots
    # - Must start and end with a lowercase letter or number
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.gcs_bucket_name))
    error_message = "Invalid GCS bucket name. Must be 3-63 characters, contain only lowercase letters, numbers, hyphens, underscores, and dots, and must start and end with a lowercase letter or number."
  }
}

variable "tf_state_bucket" {
  description = "The name of the GCS bucket for Terraform state."
  type        = string
}

# Added: Variable for the new public assets bucket
variable "assets_bucket_name" {
  description = "The name of the GCS bucket for public static assets."
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "The tag for the Docker image."
  type        = string
  default     = "latest"
}

variable "backup_dir" {
  description = "The absolute path of the directory to back up."
  type        = string

  validation {
    condition     = can(regex("^/", var.backup_dir))
    error_message = "The backup_dir must be an absolute path (e.g., '/var/www/html')."
  }
}

variable "project_id" {
  description = "The ID of the GCP project."
  type        = string
}

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
  description = "Enable the Cloud Run service. DISABLED to prevent costs."
  type        = bool
  default     = false
}

variable "enable_cloud_run_domain_mapping" {
  description = "Map the custom domain to Cloud Run. WARNING: Causes conflict if VM is also enabled with the same domain."
  type        = bool
  default     = false
}

variable "enable_firestore_database" {
  description = "Enable the creation of the Firestore database."
  type        = bool
  default     = true
}

variable "enable_gke" {
  description = <<EOT
    Enable the GKE cluster.
    ⚠️ WARNING: GKE Autopilot incurs compute costs:
    - Minimum: ~$20-30/month for 1 replica with minimal resources
    - Cost is for vCPU (250m) and Memory (512Mi) usage
    - Scaling up will significantly increase costs
    - Not part of Always Free tier
    - Management fee is waived, but compute resources are billed
  EOT
  type        = bool
  default     = false
}

variable "enable_cloud_armor" {
  description = "Enable the Cloud Armor security policy for the VM."
  type        = bool
  default     = false
}

# --- Region & Machine Config ---

variable "region" {
  description = "The region to deploy the resources in."
  type        = string
  default     = "us-central1"
}

variable "artifact_registry_region" {
  description = "The region where the Artifact Registry is located (defaults to setup script value)."
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

variable "budget_amount" {
  description = "The amount to set the budget alert at."
  type        = string
  default     = "1"

  validation {
    condition     = can(tonumber(var.budget_amount)) && tonumber(var.budget_amount) > 0
    error_message = "Budget amount must be a positive number."
  }
}

variable "cost_killer_shutdown_threshold" {
  description = "The budget threshold at which to trigger the VM shutdown (e.g., 1.0 for 100%)."
  type        = number
  default     = 1.0
}

variable "backup_threshold_hours" {
  description = "The number of hours after which a backup is considered overdue."
  type        = number
  default     = 25
}

variable "gke_cluster_name" {
  description = "The name of the GKE cluster."
  type        = string
  default     = "gke-autopilot-cluster"
}

variable "nodejs_version" {
  description = "The Node.js runtime version for Cloud Functions. This value *must* align with the version specified in `app/.nvmrc`."
  type        = string
  default     = "20" # Default kept for manual Terraform runs, but should be overridden by CI/CD
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = ""
}
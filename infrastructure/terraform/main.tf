terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.80"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Validate that VM and Cloud Run domain mapping are not both enabled
resource "null_resource" "validate_config" {
  lifecycle {
    precondition {
      condition     = !(var.enable_vm && var.enable_cloud_run_domain_mapping)
      error_message = "Cannot enable both VM and Cloud Run domain mapping on the same domain. Please set only one to true."
    }
  }
}

# Add validation

resource "null_resource" "validate_firestore" {
  lifecycle {
    precondition {
      condition     = !var.enable_cloud_run || var.enable_firestore_database
      error_message = "Firestore database is required when Cloud Run is enabled."
    }
  }
}

locals {
  environment     = terraform.workspace
  resource_prefix = var.name_prefix != "" ? "${var.name_prefix}-" : ""

  # Environment-specific overrides
  config = {
    dev = {
      enable_vm        = true
      enable_cloud_run = false
      enable_gke       = false
    }
    staging = {
      enable_vm        = false
      enable_cloud_run = true
      enable_gke       = false
    }
    prod = {
      enable_vm        = true
      enable_cloud_run = true
      enable_gke       = true
    }
  }
}

# Enable Firestore API
resource "google_project_service" "firestore" {
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

# Check if default database already exists
data "google_firestore_database" "existing" {
  count    = var.enable_firestore_database ? 1 : 0
  project  = var.project_id
  database = "(default)"

  depends_on = [google_project_service.firestore]
}

# Only create the database if it doesn't already exist
# This prevents "database already exists" errors on subsequent Terraform runs
resource "google_firestore_database" "database" {
  count       = var.enable_firestore_database && (length(data.google_firestore_database.existing[*].id) == 0 || data.google_firestore_database.existing[0].id == "") ? 1 : 0
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.firestore]
}

# Deploy Firestore security rules
# Note: Firestore security rules are managed separately via deployment or the Firebase Console.
# The firestore.rules file can be deployed using the Firebase CLI:
# firebase deploy --only firestore:rules
# Uncomment the resource below if using a custom provider or if rules management is needed via Terraform.
# For now, this is kept as documentation of the rules file location.

# --- Service Account & IAM ---

resource "google_service_account" "vm_sa" {
  count        = var.enable_vm ? 1 : 0
  account_id   = "${local.resource_prefix}free-tier-vm-sa"
  display_name = "${local.resource_prefix}Free Tier VM Service Account"
}

resource "google_project_iam_member" "log_writer" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

resource "google_project_iam_member" "metric_writer" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

resource "google_project_iam_member" "secret_accessor" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# --- Compute Engine ---

resource "google_compute_instance" "default" {
  count        = var.enable_vm ? 1 : 0
  name         = "${local.resource_prefix}free-tier-vm"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "projects/${var.image_project}/global/images/family/${var.image_family}"
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network = "default"
    access_config {
      # Ephemeral public IP
    }
  }

  tags = ["${local.resource_prefix}http-server", "${local.resource_prefix}https-server"]

  metadata_startup_script = templatefile("${path.module}/startup-script.sh.tpl", {
    gcs_bucket_name           = google_storage_bucket.backup_bucket[0].name,
    setup_scripts_tarball_md5 = data.archive_file.setup_scripts_archive.output_md5,
  })

  service_account {
    email = google_service_account.vm_sa[0].email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/devstorage.read_write"
    ]
  }

  depends_on = [
    google_storage_bucket_object.setup_scripts_tarball
  ]
}

resource "google_compute_firewall" "allow_http_https" {
  # Note: 0.0.0.0/0 is necessary for public web access.
  # For production environments, consider adding Cloud Armor for DDoS protection and rate limiting.
  count   = var.enable_vm ? 1 : 0
  name    = "${local.resource_prefix}allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags   = ["${local.resource_prefix}http-server", "${local.resource_prefix}https-server"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_security_policy" "policy" {
  count = var.enable_vm && var.enable_cloud_armor ? 1 : 0
  name  = "${local.resource_prefix}vm-security-policy"

  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
  }
}



# --- VM Health Check ---
resource "google_compute_health_check" "vm_health" {
  count = var.enable_vm ? 1 : 0
  name  = "${local.resource_prefix}vm-health-check"

  tcp_health_check {
    port = "80"
  }
}

# --- Backups Bucket ---

resource "google_storage_bucket" "backup_bucket" {
  count                       = var.enable_vm ? 1 : 0
  name                        = "${local.resource_prefix}${var.gcs_bucket_name}"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "vm_bucket_admin" {
  count  = var.enable_vm ? 1 : 0
  bucket = google_storage_bucket.backup_bucket[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

data "archive_file" "setup_scripts_archive" {
  type        = "tgz"
  source_dir  = "${path.module}/../2-host-setup"
  output_path = "${path.module}/setup-scripts.tar.gz"
}

resource "google_storage_bucket_object" "setup_scripts_tarball" {
  count  = var.enable_vm ? 1 : 0
  name   = "setup-scripts/setup-scripts.tar.gz"
  source = data.archive_file.setup_scripts_archive.output_path
  bucket = google_storage_bucket.backup_bucket[0].name
}

# --- Static Assets Bucket (NEW) ---

resource "google_storage_bucket" "assets_bucket" {
  count                       = var.assets_bucket_name != "" ? 1 : 0
  name                        = "${local.resource_prefix}${var.assets_bucket_name}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # CAUTION: Deletes bucket even if it has files

  # Add lifecycle rules for cost optimization
  lifecycle_rule {
    condition {
      age = 30 # Delete objects older than 30 days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5 # Keep only 5 non-current versions
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  cors {
    origin          = ["https://${var.domain_name}"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }
}

# Make the assets bucket public
resource "google_storage_bucket_iam_member" "assets_public_read" {
  count  = var.assets_bucket_name != "" ? 1 : 0
  bucket = google_storage_bucket.assets_bucket[0].name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Upload a demo asset
resource "google_storage_bucket_object" "demo_asset" {
  count        = var.assets_bucket_name != "" ? 1 : 0
  name         = "message.txt"
  content      = "This is a static asset served from Google Cloud Storage!"
  content_type = "text/plain"
  bucket       = google_storage_bucket.assets_bucket[0].name
}

# --- Monitoring (VM Specific) ---

resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_vm ? 1 : 0
  display_name = "${local.resource_prefix}Admin On-Call"
  type         = "email"
  labels = {
    email_address = var.email_address
  }
}

resource "google_monitoring_uptime_check_config" "http" {
  count        = var.enable_vm ? 1 : 0
  display_name = "${local.resource_prefix}Uptime check for ${var.domain_name}"
  timeout      = "10s"
  period       = "60s"
  http_check {
    path    = "/"
    port    = "443"
    use_ssl = true
  }
  monitored_resource {
    type = "uptime_url"
    labels = {
      host = var.domain_name
    }
  }
}

resource "google_monitoring_alert_policy" "default" {
  count        = var.enable_vm ? 1 : 0
  display_name = "[${local.resource_prefix}${var.domain_name}] Site Down"
  combiner     = "OR"
  notification_channels = [
    google_monitoring_notification_channel.email[0].name,
  ]
  conditions {
    display_name = "Uptime check failed on ${var.domain_name}"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.check_id=\"${google_monitoring_uptime_check_config.http[0].uptime_check_id}\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      trigger {
        count = 1
      }
      aggregations {
        alignment_period     = "60s"
        cross_series_reducer = "REDUCE_MEAN"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
      }
    }
  }
  documentation {
    content = "The uptime check for https://${var.domain_name} failed. The server may be down or misconfigured."
  }
}

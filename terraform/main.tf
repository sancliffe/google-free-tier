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
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --- Service Account & IAM ---

resource "google_service_account" "vm_sa" {
  count        = var.enable_vm ? 1 : 0
  account_id   = "free-tier-vm-sa"
  display_name = "Free Tier VM Service Account"
}

# Allow writing logs
resource "google_project_iam_member" "log_writer" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# Allow writing metrics
resource "google_project_iam_member" "metric_writer" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# Allow accessing secrets
resource "google_project_iam_member" "secret_accessor" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# --- Compute Engine ---

resource "google_compute_instance" "default" {
  count        = var.enable_vm ? 1 : 0
  name         = "free-tier-vm"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "${var.image_family}/${var.image_project}"
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

  tags = ["http-server", "https-server"]

  # Use file() instead of deprecated template_file data source
  metadata_startup_script = file("startup-script.sh.tpl")

  service_account {
    email  = google_service_account.vm_sa[0].email
    scopes = ["cloud-platform"]
  }

  # Wait for scripts to be uploaded to GCS before creating the VM.
  depends_on = [
    google_storage_bucket_object.setup_scripts
  ]
}

# Creates a firewall rule to allow HTTP and HTTPS traffic from anywhere.
resource "google_compute_firewall" "allow_http_https" {
  count   = var.enable_vm ? 1 : 0
  name    = "allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags = ["http-server", "https-server"]
  source_ranges = ["0.0.0.0/0"]
}

# Restrict SSH to IAP only
resource "google_compute_firewall" "allow_ssh_iap" {
  count   = var.enable_vm ? 1 : 0
  name    = "allow-ssh-from-iap"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["http-server", "https-server"] 
  
  # Allow connections only from Google IAP range
  source_ranges = ["35.235.240.0/20"]
}

# Bucket is needed for VM backups and storing setup scripts
resource "google_storage_bucket" "backup_bucket" {
  count         = var.enable_vm ? 1 : 0
  name          = var.gcs_bucket_name
  location      = var.region
  force_destroy = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Automatically delete backups older than 7 days
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

# Allow full control of objects ONLY for this specific bucket
resource "google_storage_bucket_iam_member" "vm_bucket_admin" {
  count  = var.enable_vm ? 1 : 0
  bucket = google_storage_bucket.backup_bucket[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# Upload the local setup scripts to the GCS bucket
resource "google_storage_bucket_object" "setup_scripts" {
  for_each = var.enable_vm ? fileset("${path.module}/../2-host-setup", "*") : []
  name     = "setup-scripts/${each.value}"
  source   = "${path.module}/../2-host-setup/${each.value}"
  bucket   = google_storage_bucket.backup_bucket[0].name
}

# --- Monitoring (VM Specific) ---

resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_vm ? 1 : 0
  display_name = "Admin On-Call"
  type         = "email"
  labels = {
    email_address = var.email_address
  }
}

resource "google_monitoring_uptime_check_config" "http" {
  count        = var.enable_vm ? 1 : 0
  display_name = "Uptime check for ${var.domain_name}"
  http_check {
    path = "/"
    port = "443"
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
  display_name = "[${var.domain_name}] Site Down"
  combiner     = "OR"
  notification_channels = [
    google_monitoring_notification_channel.email[0].name,
  ]
  conditions {
    display_name = "Uptime check failed on ${var.domain_name}"
    condition_threshold {
      filter     = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.check_id=\"${google_monitoring_uptime_check_config.http[0].uptime_check_id}\""
      duration   = "300s"
      comparison = "COMPARISON_GT"
      trigger {
        count = 1
      }
      aggregator {
        alignment_period   = "60s"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }
    }
  }
  documentation {
    content = "The uptime check for https://${var.domain_name} failed. The server may be down or misconfigured."
  }
}
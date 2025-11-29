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

# Enable Firestore API
resource "google_project_service" "firestore" {
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

# Resource to create the Firestore database
resource "google_firestore_database" "database" {
  count = var.enable_firestore_database ? 1 : 0

  project     = var.project_id
  name        = "(default)"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"
  
  lifecycle {
    # Prevent accidental deletion
    prevent_destroy = true
  }
}

# --- Service Account & IAM ---

resource "google_service_account" "vm_sa" {
  count        = var.enable_vm ? 1 : 0
  account_id   = "free-tier-vm-sa"
  display_name = "Free Tier VM Service Account"
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
  name         = "free-tier-vm"
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

  tags = ["http-server", "https-server"]

  metadata_startup_script = templatefile("${path.module}/startup-script.sh.tpl", {
    gcs_bucket_name = google_storage_bucket.backup_bucket[0].name
  })

  service_account {
    email  = google_service_account.vm_sa[0].email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/devstorage.read_write"
    ]
  }

  depends_on = [
    google_storage_bucket_object.setup_scripts
  ]
}

resource "google_compute_firewall" "allow_http_https" {
  # Note: 0.0.0.0/0 is necessary for public web access.
  # For production environments, consider adding Cloud Armor for DDoS protection and rate limiting.
  count   = var.enable_vm ? 1 : 0
  name    = "allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags   = ["http-server", "https-server"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_ssh_iap" {
  count   = var.enable_vm ? 1 : 0
  name    = "allow-ssh-from-iap"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags   = ["http-server", "https-server"]
  source_ranges = ["35.235.240.0/20"]
}

# --- Backups Bucket ---

resource "google_storage_bucket" "backup_bucket" {
  count                       = var.enable_vm ? 1 : 0
  name                        = var.gcs_bucket_name
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

resource "google_storage_bucket_object" "setup_scripts" {
  for_each = var.enable_vm ? fileset("${path.module}/../2-host-setup", "*") : []
  name     = "setup-scripts/${each.value}"
  source   = "${path.module}/../2-host-setup/${each.value}"
  bucket   = google_storage_bucket.backup_bucket[0].name
}

# --- Static Assets Bucket (NEW) ---

resource "google_storage_bucket" "assets_bucket" {
  count                       = var.assets_bucket_name != "" ? 1 : 0
  name                        = var.assets_bucket_name
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
  display_name = "[${var.domain_name}] Site Down"
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

# --- Cloud Monitoring Dashboard ---
resource "google_monitoring_dashboard" "vm_dashboard" {
  count        = var.enable_vm ? 1 : 0
  project      = var.project_id
  dashboard_json = file("${path.module}/dashboards/vm-dashboard.json")
}
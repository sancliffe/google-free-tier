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
  account_id   = "free-tier-vm-sa"
  display_name = "Free Tier VM Service Account"
}

# Allow writing logs (required for Cloud Logging agent)
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Allow writing metrics (required for Cloud Monitoring agent)
resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Allow full control of objects for backups (Write new, Delete old)
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

# --- Compute Engine ---

# Creates a Google Compute Engine instance.
resource "google_compute_instance" "default" {
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
  }

  tags = ["http-server", "https-server"]

  metadata_startup_script = data.template_file.startup_script.rendered

  # Use the custom service account with full cloud-platform access scope,
  # but restricted by the IAM roles assigned above.
  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }
}

data "template_file" "startup_script" {
  template = file("startup-script.sh.tpl")

  vars = {
    domain_name     = var.domain_name
    duckdns_token   = var.duckdns_token
    email_address   = var.email_address
    gcs_bucket_name = var.gcs_bucket_name
    backup_dir      = var.backup_dir
  }
}

# Creates a firewall rule to allow HTTP and HTTPS traffic.
resource "google_compute_firewall" "default" {
  name    = "allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags = ["http-server", "https-server"]
}

resource "google_storage_bucket" "backup_bucket" {
  name          = var.gcs_bucket_name
  location      = var.region
  force_destroy = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

# Creates a notification channel to send alerts to your email.
resource "google_monitoring_notification_channel" "email" {
  display_name = "Admin On-Call"
  type         = "email"
  labels = {
    email_address = var.email_address
  }
}

# Creates an uptime check to monitor your website's availability.
resource "google_monitoring_uptime_check_config" "http" {
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

# Creates an alerting policy to notify you if your site goes down.
resource "google_monitoring_alert_policy" "default" {
  display_name = "[${var.domain_name}] Site Down"
  combiner     = "OR"
  notification_channels = [
    google_monitoring_notification_channel.email.name,
  ]
  conditions {
    display_name = "Uptime check failed on ${var.domain_name}"
    condition_threshold {
      filter     = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.check_id=\"${google_monitoring_uptime_check_config.http.uptime_check_id}\""
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

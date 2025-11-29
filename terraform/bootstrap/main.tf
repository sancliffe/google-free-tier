terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.80"
    }
  }
}

provider "google" {
  project = var.project_id
}

resource "google_project_service" "kms" {
  service                    = "cloudkms.googleapis.com"
  disable_dependent_services = true
}

resource "google_kms_key_ring" "terraform_state_bucket" {
  name     = "terraform-state-bucket"
  location = "global"

  depends_on = [
    google_project_service.kms
  ]
}

resource "google_kms_crypto_key" "terraform_state_bucket" {
  name            = "terraform-state-bucket-key"
  key_ring        = google_kms_key_ring.terraform_state_bucket.id
  rotation_period = "100000s"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_storage_bucket" "tfstate" {
  name          = "${var.project_id}-tfstate"
  location      = "US" # Multi-regional for high availability
  force_destroy = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.terraform_state_bucket.id
  }

  logging {
    destination = google_storage_bucket.tfstate_logs.name
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    google_kms_crypto_key.terraform_state_bucket
  ]
}

resource "google_storage_bucket" "tfstate_logs" {
  name          = "${var.project_id}-tfstate-logs"
  location      = "US"
  force_destroy = false
  uniform_bucket_level_access = true

  lifecycle {
    prevent_destroy = true
  }
}

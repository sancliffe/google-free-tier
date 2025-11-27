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

resource "google_storage_bucket" "tfstate" {
  name          = "${var.project_id}-tfstate"
  location      = "US" # Multi-regional for high availability
  force_destroy = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
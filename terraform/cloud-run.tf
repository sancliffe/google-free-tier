# Enable the necessary APIs for Cloud Run and Artifact Registry.
resource "google_project_service" "cloud_run_apis" {
  for_each = var.enable_cloud_run ? toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "domains.googleapis.com",
    "firestore.googleapis.com" # Added: Enable Firestore API
  ]) : []
  service = each.key
}

# --- Security: Dedicated Service Account ---
resource "google_service_account" "cloud_run_sa" {
  count        = var.enable_cloud_run ? 1 : 0
  account_id   = "hello-cloud-run-sa"
  display_name = "Cloud Run Service Account"
}

# Grant the Service Account permission to pull images from Artifact Registry
resource "google_project_iam_member" "ar_reader" {
  count   = var.enable_cloud_run ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.cloud_run_sa[0].email}"
}

# Added: Grant the Service Account permission to access Firestore (Datastore)
resource "google_project_iam_member" "firestore_user" {
  count   = var.enable_cloud_run ? 1 : 0
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa[0].email}"
}

# --- Cloud Run Service ---
resource "google_cloud_run_v2_service" "default" {
  count    = var.enable_cloud_run ? 1 : 0
  name     = "hello-cloud-run"
  location = var.region

  template {
    # Link the dedicated service account
    service_account = google_service_account.cloud_run_sa[0].email

    containers {
      image = "${var.artifact_registry_region}-docker.pkg.dev/${var.project_id}/gke-apps/hello-cloud-run:${var.image_tag}"
      
      # Inject the version/tag as an environment variable
      env {
        name  = "APP_VERSION"
        value = var.image_tag
      }
      
      # Inject Project ID for Firestore auto-discovery
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }

      # Added: Inject URL for static assets bucket
      env {
        name  = "ASSETS_URL"
        value = "https://storage.googleapis.com/${google_storage_bucket.assets_bucket.name}"
      }

      startup_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 3
        failure_threshold     = 3
        tcp_socket {
          port = 8080
        }
      }

      liveness_probe {
        http_get {
          path = "/"
          port = 8080
        }
        period_seconds    = 10
        timeout_seconds   = 5
        failure_threshold = 3
      }
    }
  }

  traffic {
    percent         = 100
    type            = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_project_service.cloud_run_apis,
    google_project_iam_member.ar_reader
  ]
}

resource "google_cloud_run_service_iam_binding" "default" {
  count    = var.enable_cloud_run ? 1 : 0
  location = google_cloud_run_v2_service.default[0].location
  name     = google_cloud_run_v2_service.default[0].name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

resource "google_cloud_run_domain_mapping" "default" {
  count    = (var.enable_cloud_run && var.enable_cloud_run_domain_mapping) ? 1 : 0
  location = var.region
  name     = var.domain_name

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.default[0].name
  }

  depends_on = [
    google_cloud_run_v2_service.default
  ]
}
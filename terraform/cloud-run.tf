# Enable the necessary APIs for Cloud Run and Artifact Registry.
resource "google_project_service" "cloud_run_apis" {
  for_each = var.enable_cloud_run ? toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "domains.googleapis.com"
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

# --- Cloud Run Service ---
resource "google_cloud_run_v2_service" "default" {
  count    = var.enable_cloud_run ? 1 : 0
  name     = "hello-cloud-run"
  location = var.region

  template {
    # Link the dedicated service account
    service_account = google_service_account.cloud_run_sa[0].email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/gke-apps/hello-cloud-run:${var.image_tag}"
    }
  }

  traffic {
    percent         = 100
    type            = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_project_service.cloud_run_apis,
    google_project_iam_member.ar_reader # Wait for permissions to propagate
  ]
}

# Allow unauthenticated access to the Cloud Run service.
resource "google_cloud_run_service_iam_binding" "default" {
  count    = var.enable_cloud_run ? 1 : 0
  location = google_cloud_run_v2_service.default[0].location
  name     = google_cloud_run_v2_service.default[0].name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

# Map the custom domain to the Cloud Run service (Optional)
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
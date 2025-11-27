# Enable the necessary APIs for Cloud Run and Artifact Registry.
resource "google_project_service" "cloud_run_apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  service = each.key
}

# Create a Cloud Run service.
resource "google_cloud_run_v2_service" "default" {
  name     = "hello-cloud-run"
  location = var.region

  template {
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
  ]
}

# Allow unauthenticated access to the Cloud Run service.
resource "google_cloud_run_service_iam_binding" "default" {
  location = google_cloud_run_v2_service.default.location
  name     = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

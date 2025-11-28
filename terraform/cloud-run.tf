# Enable the necessary APIs for Cloud Run and Artifact Registry.
resource "google_project_service" "cloud_run_apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "domains.googleapis.com" # Added for domain mapping support
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

# Map the custom domain to the Cloud Run service
resource "google_cloud_run_domain_mapping" "default" {
  location = var.region
  name     = var.domain_name

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.default.name
  }

  depends_on = [
    google_cloud_run_v2_service.default
  ]
}
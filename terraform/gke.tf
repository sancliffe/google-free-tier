# Enable the necessary APIs for GKE and Artifact Registry.
resource "google_project_service" "gke_apis" {
  for_each = toset([
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  service = each.key
}

# REMOVED: google_artifact_registry_repository
# This resource is now managed by '1-gcp-setup/5-create-artifact-registry.sh'
# to prevent circular dependencies in the Cloud Build pipeline.

# Create a GKE Autopilot cluster.
resource "google_container_cluster" "default" {
  name     = var.gke_cluster_name
  location = var.region
  enable_autopilot = true
  network    = "default"
  subnetwork = "default"
  depends_on = [
    google_project_service.gke_apis,
  ]
}

# The following section is for the Kubernetes provider and resources.
# It configures the Kubernetes provider to connect to the GKE cluster created above.
provider "kubernetes" {
  host  = "https://container.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/clusters/${var.gke_cluster_name}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.default.master_auth[0].cluster_ca_certificate)
}

data "google_client_config" "default" {}

# Configure the kubectl provider
provider "kubectl" {
  host                   = google_container_cluster.default.endpoint
  cluster_ca_certificate = base64decode(google_container_cluster.default.master_auth.0.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
  load_config_file       = false
}

# Use Terraform to render the Kubernetes manifest templates
locals {
  # The path to the image is dynamically constructed
  # CHANGED: Using hardcoded 'gke-apps' because the Terraform resource was removed.
  image_url = "${var.region}-docker.pkg.dev/${var.project_id}/gke-apps/hello-gke:${var.image_tag}"

  # Render the deployment manifest
  deployment_yaml = templatefile("${path.module}/../3-gke-deployment/kubernetes/deployment.yaml.tpl", {
    image = local.image_url
  })
}

# Apply the Kubernetes manifests using the kubectl provider
resource "kubectl_manifest" "gke_deployment" {
  yaml_body = local.deployment_yaml
  depends_on = [
    google_container_cluster.default,
  ]
}

resource "kubectl_manifest" "gke_service" {
  yaml_body = file("${path.module}/../3-gke-deployment/kubernetes/service.yaml")
  depends_on = [
    kubectl_manifest.gke_deployment,
  ]
}
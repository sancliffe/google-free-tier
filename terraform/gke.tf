# Enable the necessary APIs for GKE.
resource "google_project_service" "gke_apis" {
  for_each = var.enable_gke ? toset([
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "firestore.googleapis.com" # Added: Enable Firestore API
  ]) : []
  service = each.key
}

# Create a GKE Autopilot cluster.
resource "google_container_cluster" "default" {
  count            = var.enable_gke ? 1 : 0
  name             = var.gke_cluster_name
  location         = var.region
  enable_autopilot = true
  network          = "default"
  subnetwork       = "default"
  
  # Allow Terraform to destroy the cluster without manual intervention
  deletion_protection = false

  depends_on = [
    google_project_service.gke_apis,
  ]
}

data "google_client_config" "default" {}

# Configure the Kubernetes provider.
# We use 'try' to handle cases where the GKE cluster is not enabled (count = 0).
provider "kubernetes" {
  host                   = try(google_container_cluster.default[0].endpoint, "")
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = try(base64decode(google_container_cluster.default[0].master_auth[0].cluster_ca_certificate), "")
}

# Configure the Kubectl provider.
provider "kubectl" {
  host                   = try(google_container_cluster.default[0].endpoint, "")
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = try(base64decode(google_container_cluster.default[0].master_auth[0].cluster_ca_certificate), "")
  load_config_file       = false
}

locals {
  # Construct image URL using the correct artifact registry region
  image_url = "${var.artifact_registry_region}-docker.pkg.dev/${var.project_id}/gke-apps/hello-gke:${var.image_tag}"

  # Render the deployment manifest
  deployment_yaml = templatefile("${path.module}/../3-gke-deployment/kubernetes/deployment.yaml.tpl", {
    image = local.image_url
  })
}

# Apply the Kubernetes manifests
resource "kubectl_manifest" "gke_deployment" {
  count      = var.enable_gke ? 1 : 0
  yaml_body  = local.deployment_yaml
  depends_on = [
    google_container_cluster.default,
  ]
}

resource "google_compute_global_address" "gke_static_ip" {
  count = var.enable_gke ? 1 : 0
  name  = "gke-static-ip"
}

resource "kubectl_manifest" "gke_service" {
  count      = var.enable_gke ? 1 : 0
  yaml_body  = file("${path.module}/../3-gke-deployment/kubernetes/service.yaml")
  depends_on = [
    kubectl_manifest.gke_deployment,
  ]
}

resource "kubectl_manifest" "managed_certificate" {
  count      = var.enable_gke ? 1 : 0
  yaml_body  = templatefile("${path.module}/../3-gke-deployment/kubernetes/managed-certificate.yaml.tpl", {
    domain_name = var.domain_name
  })
  depends_on = [
    google_container_cluster.default,
  ]
}

resource "kubectl_manifest" "ingress" {
  count      = var.enable_gke ? 1 : 0
  yaml_body  = file("${path.module}/../3-gke-deployment/kubernetes/ingress.yaml")
  depends_on = [
    kubectl_manifest.gke_service,
  ]
}
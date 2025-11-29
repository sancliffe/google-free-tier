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
  
  deletion_protection = false

  depends_on = [
    google_project_service.gke_apis,
  ]
}

resource "google_project_iam_member" "gke_firestore_user" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${var.project_id}.svc.id.goog[default/default]"
  depends_on = [
    google_container_cluster.default,
  ]
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = var.enable_gke ? google_container_cluster.default[0].endpoint : ""
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = var.enable_gke ? base64decode(google_container_cluster.default[0].master_auth[0].cluster_ca_certificate) : ""
}

provider "kubectl" {
  host                   = var.enable_gke ? google_container_cluster.default[0].endpoint : ""
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = var.enable_gke ? base64decode(google_container_cluster.default[0].master_auth[0].cluster_ca_certificate) : ""
  load_config_file       = false
}

locals {
  image_url = "${var.artifact_registry_region}-docker.pkg.dev/${var.project_id}/gke-apps/hello-app:${var.image_tag}"

  # Pass variables to the deployment template
  deployment_yaml = templatefile("${path.module}/../3-gke-deployment/kubernetes/deployment.yaml.tpl", {
    image      = local.image_url
    project_id = var.project_id
    assets_url = var.assets_bucket_name != "" ? "https://storage.googleapis.com/${google_storage_bucket.assets_bucket[0].name}" : ""
  })
}

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
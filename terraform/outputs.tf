output "instance_name" {
  description = "The name of the GCE instance."
  value       = google_compute_instance.default.name
}

output "instance_public_ip" {
  description = "The public IP address of the GCE instance."
  value       = google_compute_instance.default.network_interface[0].access_config[0].nat_ip
}

output "gke_cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.default.name
}

data "kubernetes_service" "hello_gke_service" {
  metadata {
    name = "hello-gke-service"
  }
}

output "kubernetes_service_ip" {
  description = "The public IP address of the Kubernetes service."
  value       = data.kubernetes_service.hello_gke_service.status.0.load_balancer.0.ingress.0.ip
}

output "region" {
  description = "The region where the resources are deployed."
  value       = var.region
}

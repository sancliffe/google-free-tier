output "instance_name" {
  description = "The name of the GCE instance."
  value       = google_compute_instance.default.name
}

output "instance_public_ip" {
  description = "The public IP address of the GCE instance."
  value       = google_compute_instance.default.network_interface[0].access_config[0].nat_ip
}

output "cloud_run_service_url" {
  description = "The default URL of the Cloud Run service (run.app)."
  value       = google_cloud_run_v2_service.default.uri
}

output "cloud_run_custom_domain" {
  description = "The custom domain URL mapped to Cloud Run."
  value       = "https://${var.domain_name}"
}

output "region" {
  description = "The region where the resources are deployed."
  value       = var.region
}
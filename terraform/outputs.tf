output "instance_name" {
  description = "The name of the GCE instance."
  # Use 'one' to handle the list resulting from 'count'. Returns null if list is empty.
  value = one(google_compute_instance.default[*].name)
}

output "instance_public_ip" {
  description = "The public IP address of the GCE instance."
  # specific complexity here requires try because access_config is a nested list
  value = try(google_compute_instance.default[0].network_interface[0].access_config[0].nat_ip, null)
}

output "cloud_run_service_url" {
  description = "The default URL of the Cloud Run service (run.app)."
  value       = one(google_cloud_run_v2_service.default[*].uri)
}

output "cloud_run_custom_domain" {
  description = "The custom domain URL mapped to Cloud Run."
  # Return the domain only if Cloud Run mapping is actually enabled
  value = (var.enable_cloud_run && var.enable_cloud_run_domain_mapping) ? "https://${var.domain_name}" : null
}

output "region" {
  description = "The region where the resources are deployed."
  value       = var.region
}
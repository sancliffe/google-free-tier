variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "image_family" {
  type    = string
  default = "debian-12"
}

variable "image_project" {
  type    = string
  default = "debian-cloud"
}

variable "machine_type" {
  type    = string
  default = "e2-micro"
}

variable "image_name" {
  type    = string
  default = "gcp-free-tier-nginx-{{timestamp}}"
}

source "googlecompute" "gce" {
  project_id   = var.project_id
  zone         = var.zone
  source_image_family = var.image_family
  source_image_project_id = var.image_project
  machine_type = var.machine_type
  image_name   = var.image_name
  ssh_username = "packer"
}

build {
  sources = ["source.googlecompute.gce"]

  provisioner "shell" {
    # FIXED: Enforce strict error checking
    valid_exit_codes = [0]
    inline = [
      "set -euxo pipefail",  # Add -x for debugging
      "sudo apt-get update",
      "sudo apt-get install -y nginx"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../2-host-setup"
    destination = "/tmp"
  }

  provisioner "shell" {
    valid_exit_codes = [0]
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "set -euxo pipefail",  # Add -x for debugging
      "sudo chmod +x /tmp/2-host-setup/*.sh",
      "sudo /tmp/2-host-setup/1-create-swap.sh",
      "sudo /tmp/2-host-setup/2-install-nginx.sh",
      # Note: Skipping DuckDNS, SSL, Backup, and Security setup
      # to keep the image generic and accessible.
      "echo 'Cleaning up temporary setup scripts...'",
      "sudo rm -rf /tmp/2-host-setup"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
    strip_path = true
  }
}
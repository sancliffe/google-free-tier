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
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y nginx"
    ]
  }

  provisioner "file" {
    source      = "../2-host-setup"
    destination = "/tmp"
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "sudo chmod +x /tmp/2-host-setup/*.sh",
      "sudo /tmp/2-host-setup/1-create-swap.sh",
      "sudo /tmp/2-host-setup/2-install-nginx.sh",
      "echo 'Note: Skipping DuckDNS, SSL, and backup setup in Packer image.'",
      "echo 'These often require live credentials and are better handled on first boot or via a different mechanism.'",
      "echo 'Cleaning up temporary setup scripts...'",
      "sudo rm -rf /tmp/2-host-setup"
    ]
  }
}
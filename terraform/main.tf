locals {
  ssh_keys = "${var.ssh_user}:${trimspace(var.ssh_public_key)}"

  instances = {
    backend-vm = {
      machine_type = var.backend_vm_machine_type
      disk_size_gb = var.backend_vm_disk_size_gb
      internal_ip  = "10.0.0.11"
      tags         = ["myapp", "k3s", "control-plane", "backend-vm"]
      public_ip    = false
    }
    frontend-vm = {
      machine_type = var.frontend_vm_machine_type
      disk_size_gb = var.frontend_vm_disk_size_gb
      internal_ip  = "10.0.0.12"
      tags         = ["myapp", "k3s", "worker", "frontend-vm", "jumphost", "public-ingress"]
      public_ip    = true
    }
    backend2 = {
      machine_type = var.backend2_machine_type
      disk_size_gb = var.backend2_disk_size_gb
      internal_ip  = "10.0.0.13"
      tags         = ["myapp", "k3s", "worker", "backend2"]
      public_ip    = false
    }
  }
}

resource "google_compute_network" "myapp" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "myapp" {
  name          = var.subnetwork_name
  region        = var.region
  network       = google_compute_network.myapp.id
  ip_cidr_range = var.subnetwork_cidr
}

resource "google_compute_router" "myapp_nat_router" {
  name    = "myapp-nat-router"
  region  = var.region
  network = google_compute_network.myapp.id
}

resource "google_compute_router_nat" "myapp_nat" {
  name                               = "myapp-cloud-nat"
  router                             = google_compute_router.myapp_nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.myapp.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_address" "frontend_vm_public_ip" {
  name   = "frontend-vm-public-ip"
  region = var.region
}

resource "google_compute_firewall" "allow_frontend_public" {
  name    = "myapp-allow-frontend-public"
  network = google_compute_network.myapp.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["public-ingress"]
}

resource "google_compute_firewall" "allow_frontend_ssh" {
  name    = "myapp-allow-frontend-ssh"
  network = google_compute_network.myapp.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.admin_source_ranges
  target_tags   = ["jumphost"]
}

resource "google_compute_firewall" "allow_internal_cluster" {
  name    = "myapp-allow-internal-cluster"
  network = google_compute_network.myapp.name

  allow {
    protocol = "tcp"
    ports    = ["22", "6443", "10250", "2379-2380"]
  }

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnetwork_cidr]
  target_tags   = ["k3s"]
}

resource "google_compute_instance" "myapp" {
  for_each     = local.instances
  name         = each.key
  zone         = var.zone
  machine_type = each.value.machine_type
  tags         = each.value.tags

  boot_disk {
    auto_delete = true

    initialize_params {
      image = var.image
      size  = each.value.disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = google_compute_network.myapp.id
    subnetwork = google_compute_subnetwork.myapp.id
    network_ip = each.value.internal_ip

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {
        nat_ip       = google_compute_address.frontend_vm_public_ip.address
        network_tier = "PREMIUM"
      }
    }
  }

  metadata = {
    ssh-keys = local.ssh_keys
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}

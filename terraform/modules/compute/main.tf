# ── Service Account ───────────────────────────────────────
# Dedicated service account for cluster nodes with minimal permissions
# Original used default compute service account which has too broad access
resource "google_service_account" "rke2_nodes" {
  account_id   = "myapp-rke2-nodes"
  display_name = "MyApp RKE2 Nodes"
  description  = "Service account for RKE2 cluster nodes - minimal permissions"
}

# ── Reserved Public IP ────────────────────────────────────
# Static public IP for worker-01 (bastion + ingress)
# Reserved separately so it survives VM recreation
# If we hardcoded the IP inside the VM resource,
# destroying and recreating the VM would get a new IP
# and break DNS
resource "google_compute_address" "worker_01_public_ip" {
  name        = "myapp-worker-01-public-ip"
  region      = split("-", split("/", var.zone)[0])[0]
  description = "Reserved static public IP for myapp-worker-01 (bastion + ingress)"
}

# ── Startup Script ────────────────────────────────────────
# Basic OS hardening applied to all nodes on first boot
locals {
  startup_script = <<-EOF
    #!/bin/bash
    set -e

    # Disable password authentication - key only
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart sshd

    # Update package list and apply security patches
    apt-get update -qq
    apt-get upgrade -y -qq

    # Disable unused filesystems
    echo "install cramfs /bin/true" >> /etc/modprobe.d/hardening.conf
    echo "install freevxfs /bin/true" >> /etc/modprobe.d/hardening.conf
    echo "install jffs2 /bin/true" >> /etc/modprobe.d/hardening.conf
    echo "install hfs /bin/true" >> /etc/modprobe.d/hardening.conf
    echo "install hfsplus /bin/true" >> /etc/modprobe.d/hardening.conf
    echo "install squashfs /bin/true" >> /etc/modprobe.d/hardening.conf
    echo "install udf /bin/true" >> /etc/modprobe.d/hardening.conf

    # Set correct permissions on sensitive files
    chmod 600 /etc/ssh/sshd_config
    chmod 700 /root
  EOF
}

# ── myapp-cp-01 ────────────────────────────────────────
# Control-plane node — runs RKE2 server
# Private only — no public IP
resource "google_compute_instance" "cp_01" {
  name         = "myapp-cp-01"
  machine_type = var.machine_type
  zone         = var.zone
  description  = "RKE2 control-plane node"

  tags = ["rke2-node", "rke2-server"]

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.vpc_name
    subnetwork = var.subnet_name
    network_ip = var.cp_01_ip
    # No access_config block = no public IP
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${var.ssh_public_key}"
    block-project-ssh-keys = "true"
    enable-oslogin         = "false"
  }

  metadata_startup_script = local.startup_script

  service_account {
    email  = google_service_account.rke2_nodes.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    # Prevent accidental destruction of the control-plane node
    # You must explicitly remove this before destroying
    prevent_destroy = true

    # Do not recreate VM if startup script or metadata changes
    ignore_changes = [
      metadata_startup_script,
      metadata
    ]
  }
}

# ── myapp-worker-01 ────────────────────────────────────
# Worker node — runs RKE2 agent
# Has public IP — acts as bastion + ingress node
resource "google_compute_instance" "worker_01" {
  name         = "myapp-worker-01"
  machine_type = var.machine_type
  zone         = var.zone
  description  = "RKE2 worker node — bastion and ingress"

  tags = ["rke2-node", "rke2-agent", "bastion", "ingress"]

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.vpc_name
    subnetwork = var.subnet_name
    network_ip = var.worker_01_ip

    # Public IP — attached from reserved static address
    access_config {
      nat_ip = google_compute_address.worker_01_public_ip.address
    }
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${var.ssh_public_key}"
    block-project-ssh-keys = "true"
    enable-oslogin         = "false"
  }

  metadata_startup_script = local.startup_script

  service_account {
    email  = google_service_account.rke2_nodes.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    ignore_changes = [
      metadata_startup_script,
      metadata
    ]
  }
}

# ── myapp-worker-02 ────────────────────────────────────
# Worker node — runs RKE2 agent
# Private only — no public IP
resource "google_compute_instance" "worker_02" {
  name         = "myapp-worker-01"
  machine_type = var.machine_type
  zone         = var.zone
  description  = "RKE2 worker node"

  tags = ["rke2-node", "rke2-agent"]

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.vpc_name
    subnetwork = var.subnet_name
    network_ip = var.worker_02_ip
    # No access_config block = no public IP
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${var.ssh_public_key}"
    block-project-ssh-keys = "true"
    enable-oslogin         = "false"
  }

  metadata_startup_script = local.startup_script

  service_account {
    email  = google_service_account.rke2_nodes.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    ignore_changes = [
      metadata_startup_script,
      metadata
    ]
  }
}
# ── VPC ───────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  description             = "MyApp cluster VPC"
}

# ── Subnet ────────────────────────────────────────────────
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  description   = "MyApp cluster subnet"

  # Enables flow logs for network traffic visibility
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ── Firewall — SSH external (bastion only) ────────────────
# Only myapp-worker-01 has a public IP and acts as bastion
# Backend nodes are only reachable via ProxyJump through it
resource "google_compute_firewall" "allow_ssh_external" {
  name        = "${var.vpc_name}-allow-ssh-external"
  network     = google_compute_network.vpc.name
  description = "Allow SSH from admin IPs to bastion node only"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.admin_source_ranges
  target_tags   = ["bastion"]
}

# ── Firewall — HTTP/HTTPS external ───────────────────────
resource "google_compute_firewall" "allow_web_external" {
  name        = "${var.vpc_name}-allow-web-external"
  network     = google_compute_network.vpc.name
  description = "Allow HTTP and HTTPS traffic from internet to ingress node"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ingress"]
}

# ── Firewall — SSH internal ───────────────────────────────
# Allows SSH between nodes via ProxyJump through bastion
resource "google_compute_firewall" "allow_ssh_internal" {
  name        = "${var.vpc_name}-allow-ssh-internal"
  network     = google_compute_network.vpc.name
  description = "Allow SSH between cluster nodes via bastion"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-node"]
}

# ── Firewall — RKE2 Kubernetes API ────────────────────────
resource "google_compute_firewall" "allow_k8s_api" {
  name        = "${var.vpc_name}-allow-k8s-api"
  network     = google_compute_network.vpc.name
  description = "Allow Kubernetes API server access within cluster"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-server"]
}

# ── Firewall — RKE2 Supervisor API ────────────────────────
resource "google_compute_firewall" "allow_rke2_supervisor" {
  name        = "${var.vpc_name}-allow-rke2-supervisor"
  network     = google_compute_network.vpc.name
  description = "Allow RKE2 supervisor API used by agent nodes to join the cluster"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["9345"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-server"]
}

# ── Firewall — etcd ───────────────────────────────────────
resource "google_compute_firewall" "allow_etcd" {
  name        = "${var.vpc_name}-allow-etcd"
  network     = google_compute_network.vpc.name
  description = "Allow etcd peer communication between server nodes"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["2379", "2380"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-server"]
}

# ── Firewall — Kubelet ────────────────────────────────────
resource "google_compute_firewall" "allow_kubelet" {
  name        = "${var.vpc_name}-allow-kubelet"
  network     = google_compute_network.vpc.name
  description = "Allow kubelet API access between nodes"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-node"]
}

# ── Firewall — Canal CNI (VXLAN) ──────────────────────────
resource "google_compute_firewall" "allow_canal_vxlan" {
  name        = "${var.vpc_name}-allow-canal-vxlan"
  network     = google_compute_network.vpc.name
  description = "Allow Canal CNI VXLAN overlay network traffic between nodes"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-node"]
}

# ── Firewall — WireGuard ──────────────────────────────────
resource "google_compute_firewall" "allow_wireguard" {
  name        = "${var.vpc_name}-allow-wireguard"
  network     = google_compute_network.vpc.name
  description = "Allow WireGuard encrypted overlay between nodes"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-node"]
}

# ── Firewall — NodePort services ──────────────────────────
resource "google_compute_firewall" "allow_nodeport" {
  name        = "${var.vpc_name}-allow-nodeport"
  network     = google_compute_network.vpc.name
  description = "Allow Kubernetes NodePort service range within cluster"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-node"]
}

# ── Firewall — ICMP internal ──────────────────────────────
resource "google_compute_firewall" "allow_icmp_internal" {
  name        = "${var.vpc_name}-allow-icmp-internal"
  network     = google_compute_network.vpc.name
  description = "Allow ICMP ping between cluster nodes for health checks"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["rke2-node"]
}
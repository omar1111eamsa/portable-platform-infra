# ── Control Plane ─────────────────────────────────────────
output "cp_01_name" {
  description = "Name of the control-plane node"
  value       = google_compute_instance.cp_01.name
}

output "cp_01_internal_ip" {
  description = "Internal IP of the control-plane node"
  value       = google_compute_instance.cp_01.network_interface[0].network_ip
}

# ── Worker 01 ─────────────────────────────────────────────
output "worker_01_name" {
  description = "Name of worker node 01"
  value       = google_compute_instance.worker_01.name
}

output "worker_01_internal_ip" {
  description = "Internal IP of worker node 01"
  value       = google_compute_instance.worker_01.network_interface[0].network_ip
}

output "worker_01_public_ip" {
  description = "Public IP of worker node 01 — used as bastion and ingress"
  value       = google_compute_address.worker_01_public_ip.address
}

# ── Worker 02 ─────────────────────────────────────────────
output "worker_02_name" {
  description = "Name of worker node 02"
  value       = google_compute_instance.worker_02.name
}

output "worker_02_internal_ip" {
  description = "Internal IP of worker node 02"
  value       = google_compute_instance.worker_02.network_interface[0].network_ip
}

# ── Cluster summary ───────────────────────────────────────
# Structured output consumed by Ansible inventory generation
output "cluster_nodes" {
  description = "Structured map of all cluster nodes — consumed by Ansible"
  value = {
    cp_01 = {
      name        = google_compute_instance.cp_01.name
      internal_ip = google_compute_instance.cp_01.network_interface[0].network_ip
      role        = "control-plane"
    }
    worker_01 = {
      name        = google_compute_instance.worker_01.name
      internal_ip = google_compute_instance.worker_01.network_interface[0].network_ip
      public_ip   = google_compute_address.worker_01_public_ip.address
      role        = "worker"
      is_bastion  = true
    }
    worker_02 = {
      name        = google_compute_instance.worker_02.name
      internal_ip = google_compute_instance.worker_02.network_interface[0].network_ip
      role        = "worker"
      is_bastion  = false
    }
  }
}
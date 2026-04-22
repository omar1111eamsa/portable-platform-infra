# ── Public access ─────────────────────────────────────────
output "bastion_public_ip" {
  description = "Public IP of the bastion node — use this for SSH access and DNS"
  value       = module.compute.worker_01_public_ip
}

# ── Internal IPs ──────────────────────────────────────────
output "cp_01_internal_ip" {
  description = "Internal IP of the control-plane node"
  value       = module.compute.cp_01_internal_ip
}

output "worker_01_internal_ip" {
  description = "Internal IP of worker node 01"
  value       = module.compute.worker_01_internal_ip
}

output "worker_02_internal_ip" {
  description = "Internal IP of worker node 02"
  value       = module.compute.worker_02_internal_ip
}

# ── DNS reminder ──────────────────────────────────────────
output "dns_reminder" {
  description = "Reminder to point DNS to the bastion public IP"
  value       = "Point dev.example.com A record to: ${module.compute.worker_01_public_ip}"
}

# ── Ansible inventory ─────────────────────────────────────
# Single structured output consumed by Ansible inventory
# generation script — one call gets everything
output "cluster_nodes" {
  description = "Structured cluster node map for Ansible inventory generation"
  value       = module.compute.cluster_nodes
}

# ── SSH config hint ───────────────────────────────────────
# Printed after apply so engineer can immediately configure SSH
output "ssh_config_hint" {
  description = "SSH config block to add to ~/.ssh/config"
  value       = <<-EOT

    Add this to ~/.ssh/config to access all nodes:

    Host myapp-bastion
      HostName      ${module.compute.worker_01_public_ip}
      User          myapp
      IdentityFile  ~/.ssh/myapp_vms

    Host myapp-cp-01
      HostName      ${module.compute.cp_01_internal_ip}
      User          myapp
      IdentityFile  ~/.ssh/myapp_vms
      ProxyJump     myapp-bastion

    Host myapp-worker-02
      HostName      ${module.compute.worker_02_internal_ip}
      User          myapp
      IdentityFile  ~/.ssh/myapp_vms
      ProxyJump     myapp-bastion

  EOT
}
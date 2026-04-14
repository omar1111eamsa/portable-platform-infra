output "frontend_public_ip" {
  description = "Reserved public IP attached to frontend-vm."
  value       = google_compute_address.frontend_vm_public_ip.address
}

output "backend_vm_private_ip" {
  description = "Private IP of backend-vm."
  value       = google_compute_instance.myapp["backend-vm"].network_interface[0].network_ip
}

output "frontend_vm_private_ip" {
  description = "Private IP of frontend-vm."
  value       = google_compute_instance.myapp["frontend-vm"].network_interface[0].network_ip
}

output "backend2_private_ip" {
  description = "Private IP of backend2."
  value       = google_compute_instance.myapp["backend2"].network_interface[0].network_ip
}

output "ansible_inventory" {
  description = "Rendered Ansible inventory matching the Terraform-created infra."
  value       = <<-EOT
    ---
    all:
      vars:
        ansible_user: ${var.ssh_user}
        ansible_ssh_private_key_file: "~/.ssh/myapp_vms"
      children:
        k3s_server:
          hosts:
            backend-vm:
              ansible_host: ${google_compute_instance.myapp["backend-vm"].network_interface[0].network_ip}
              ansible_ssh_common_args: '-o ProxyCommand="ssh -W %%h:%%p -i ~/.ssh/myapp_vms ${var.ssh_user}@${google_compute_address.frontend_vm_public_ip.address}"'
        k3s_agents:
          hosts:
            frontend-vm:
              ansible_host: ${google_compute_address.frontend_vm_public_ip.address}
            backend2:
              ansible_host: ${google_compute_instance.myapp["backend2"].network_interface[0].network_ip}
              ansible_ssh_common_args: '-o ProxyCommand="ssh -W %%h:%%p -i ~/.ssh/myapp_vms ${var.ssh_user}@${google_compute_address.frontend_vm_public_ip.address}"'
        jumphost:
          hosts:
            frontend-vm:
  EOT
}

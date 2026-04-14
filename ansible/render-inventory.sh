#!/usr/bin/env bash
set -euo pipefail

TERRAFORM_DIR="${1:-../terraform}"
OUTPUT_FILE="${2:-inventory.generated.yml}"

frontend_public_ip="$(terraform -chdir="${TERRAFORM_DIR}" output -raw frontend_public_ip)"
backend_vm_private_ip="$(terraform -chdir="${TERRAFORM_DIR}" output -raw backend_vm_private_ip)"
backend2_private_ip="$(terraform -chdir="${TERRAFORM_DIR}" output -raw backend2_private_ip)"

cat > "${OUTPUT_FILE}" <<EOF
---
all:
  vars:
    ansible_user: myapp
    ansible_ssh_private_key_file: "~/.ssh/myapp_vms"
  children:
    k3s_server:
      hosts:
        backend-vm:
          ansible_host: ${backend_vm_private_ip}
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -i ~/.ssh/myapp_vms myapp@${frontend_public_ip}"'
    k3s_agents:
      hosts:
        frontend-vm:
          ansible_host: ${frontend_public_ip}
        backend2:
          ansible_host: ${backend2_private_ip}
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -i ~/.ssh/myapp_vms myapp@${frontend_public_ip}"'
    jumphost:
      hosts:
        frontend-vm:
EOF

echo "Generated ${OUTPUT_FILE}"

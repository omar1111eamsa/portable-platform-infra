# Ansible — MyApp k3s cluster (3 VMs)

## VMs

| Host        | Role       | IP          | Access              |
|------------|------------|-------------|---------------------|
| backend-vm | k3s server | 10.0.0.11   | SSH via ProxyJump   |
| frontend-vm| k3s agent  | 203.0.113.11 | Direct (jumphost)   |
| backend2   | k3s agent  | 10.0.0.13   | SSH via ProxyJump   |

**DNS:** `dev.example.com` and `api.example.com` → A record to **203.0.113.11**.

## Usage

```bash
# Full setup (k3s + ngrok on frontend-vm only)
ansible-playbook -i inventory.yml playbook.yml

# k3s only (no ngrok)
ansible-playbook -i inventory.yml playbook-k3s-only.yml
```

**Prerequisites:** SSH key `~/.ssh/myapp_vms`, access to frontend-vm (203.0.113.11).  
After install: run `deploy/k8s/scripts/start-kubectl-tunnel.sh` then `kubectl apply -k deploy/k8s`.

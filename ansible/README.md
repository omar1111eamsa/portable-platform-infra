# Ansible — MyApp k3s cluster (3 VMs)

## VMs

| Host        | Role       | IP          | Access              |
|------------|------------|-------------|---------------------|
| backend-vm | k3s server | 10.0.0.11   | SSH via ProxyJump   |
| frontend-vm| k3s agent  | reserved public IP + 10.0.0.12 | Direct (jumphost)   |
| backend2   | k3s agent  | 10.0.0.13   | SSH via ProxyJump   |

**DNS:** `dev.example.com` → A record to the reserved public IP of `frontend-vm`.

## Infra source of truth

- Terraform is under [`terraform/`](../terraform) (**GCP**)
- Terraform creates:
  - VPC `myapp-vpc`, subnet `10.10.0.0/24`
  - `backend-vm`, `frontend-vm`, `backend2` (Ubuntu 22.04, static private IPs)
  - Firewall rules (SSH/HTTP/HTTPS + internal k3s ports)
  - Static public IP for `frontend-vm`

Generate the public IP with:

```bash
terraform -chdir=../terraform output -raw frontend_public_ip
```

Generate an Ansible inventory directly from Terraform outputs:

```bash
./render-inventory.sh ../terraform inventory.generated.yml
ansible-playbook -i inventory.generated.yml playbook.yml
```

## Usage

```bash
# Setup cluster k3s
ansible-playbook -i inventory.yml playbook.yml
```

**Prerequisites:** SSH key `~/.ssh/myapp_vms`, Terraform-applied infra, and `inventory.yml` updated with the reserved `frontend-vm` public IP.  
After install: run `deploy/k8s/scripts/start-kubectl-tunnel.sh` then `kubectl apply -k deploy/k8s`.

## Recommended: one-command bootstrap (no manual secret commands)

Use the bootstrap script to:
- render inventory from Terraform outputs
- install k3s on 3 VMs
- pull kubeconfig + start SSH tunnel
- create/update required Kubernetes secrets
- apply full stack (`deploy/k8s`)
- handle recreated-VM SSH host-key drift automatically (`ANSIBLE_HOST_KEY_CHECKING=False`)

```bash
cp ../deploy/k8s/secrets.env.example ../deploy/k8s/secrets.env
# edit ../deploy/k8s/secrets.env with real values

./bootstrap-cluster.sh
```

Useful options:

```bash
# only provision cluster + kubeconfig/tunnel (skip k8s apply)
./bootstrap-cluster.sh --skip-apply

# custom paths
./bootstrap-cluster.sh --terraform-dir ../terraform --secrets-file ../deploy/k8s/secrets.env
```

`bootstrap-cluster.sh` requires `deploy/k8s/secrets.env` to define all mandatory values used to generate Kubernetes secrets, including UI/auth variables:

- `AIRFLOW_ADMIN_PASSWORD`
- `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`
- `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`
- `CONSUL_UI_USERNAME`, `CONSUL_UI_PASSWORD`

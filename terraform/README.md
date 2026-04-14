# Terraform — MyApp Base Infra

This directory creates the base GCP infra expected by the existing Ansible and k3s manifests:

- `backend-vm` — k3s server, private only
- `frontend-vm` — k3s worker + public ingress/jumphost, reserved public IP
- `backend2` — k3s worker, private only

## Default topology

- VPC: `myapp-vpc`
- Subnet: `myapp-subnet`
- CIDR: `10.10.0.0/24`
- Static internal IPs:
  - `backend-vm` → `10.0.0.11`
  - `frontend-vm` → `10.0.0.12`
  - `backend2` → `10.0.0.13`

## Default VM sizes

- `backend-vm`: `e2-custom-2-8192` → 2 vCPU / 8 GB RAM / 20 GB disk
- `frontend-vm`: `e2-custom-2-8192` → 2 vCPU / 8 GB RAM / 10 GB disk
- `backend2`: `e2-custom-2-8192` → 2 vCPU / 8 GB RAM / 20 GB disk

## Firewall model

- Public:
  - TCP `22` to `frontend-vm` from `admin_source_ranges`
  - TCP `80,443` to `frontend-vm` from anywhere
- Internal within `10.10.0.0/24`:
  - TCP `22,6443,10250,2379-2380`
  - UDP `8472`
  - ICMP

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

terraform init
terraform plan
terraform apply
```

To generate the matching Ansible inventory:

```bash
terraform output -raw ansible_inventory
```

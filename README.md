# Backend Management Service

> **Active CI branch:** test-argocd  
> **Last sync from remote:** 2026-03-09


## Overview

This repository is the **central infrastructure and deployment control plane** for the MyApp platform.  
It orchestrates, configures, and deploys backend microservices and supporting infrastructure in a secure, reproducible, and scalable way.

**Application source code is not stored here.**  
Each backend service (user-management, api-gateway, payment-service, etc.) lives in its own dedicated repository.

---

## Repository Structure

```
portable-platform-infra/
├── ansible/                    # Ansible (k3s on 3 VMs: backend-vm, frontend-vm, backend2)
│   ├── playbook.yml           # k3s setup
│   └── roles/k3s-server, k3s-agent
├── deploy/
│   ├── k8s/                   # Kubernetes manifests (k3s) — production
│   │   ├── base/              # Namespace
│   │   ├── infra/             # Postgres, Redis, Consul, RabbitMQ
│   │   ├── apps/              # api-gateway, frontend, user-management, etc.
│   │   ├── cronjobs/          # Disk cleanup, evicted pods
│   │   └── argocd/            # ArgoCD Ingress
│   ├── local/                 # Docker Compose (local dev only)
│   ├── docs/                  # Architecture docs (INDEX.md)
│   └── argocd/                # ArgoCD Application definition
├── .env.example
└── README.md
```

---

## Responsibilities

- **Kubernetes (k3s)** : manifests, Ingress, CronJobs — production deployment
- **ArgoCD** : GitOps, watches `test-argocd`, syncs on manifest changes
- **Infrastructure** : PostgreSQL, Redis, Consul, RabbitMQ
- **Documentation** : architecture, deployment guide, checklist

---

## Domains & access

- **dev.example.com** — Frontend principal (app), API (`/api`), ArgoCD (`/argocd`), and UI tools by path (`/pgadmin`, `/rabbitmq`, `/grafana`, `/consul`, `/prometheus`)
- **airflow.dev.example.com** — Airflow UI/API host
- **dashboard.example.com** — Admin frontend
- **DNS** : A records point to the reserved public IP of `frontend-vm`. Cluster has 3 nodes: `backend-vm`, `frontend-vm`, `backend2`.

## Deployment (k8s + ArgoCD)

**Production** : ArgoCD syncs automatically from branch `test-argocd`, path `deploy/k8s`.  
See [deploy/argocd/ARGOCD-AUTODEPLOY.md](deploy/argocd/ARGOCD-AUTODEPLOY.md).

**Manual apply** :

```bash
# Prérequis : ghcr-secret, KUBECONFIG
kubectl apply -k deploy/k8s/
# Avec domaine fixe (dev.example.com) :
deploy/k8s/scripts/apply-with-domain.sh
```

See [deploy/k8s/DEPLOYMENT.md](deploy/k8s/DEPLOYMENT.md) and [deploy/SETUP.md](deploy/SETUP.md).

---

## Security

- No secrets committed to the repository
- Secrets injected at runtime (ghcr-secret, postgres-credentials, etc.)
- Backend services internal; only gateway/frontend and selected dev UIs exposed via Ingress
- UI exposure is path/host constrained; sensitive UIs (ArgoCD, pgAdmin, RabbitMQ, Grafana, Airflow, Consul) require authentication

---

## License

Proprietary — internal platform management.

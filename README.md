# Backend Management Service

## Overview

This repository is the **central infrastructure and deployment control plane** for the MyApp platform.  
It orchestrates, configures, and deploys backend microservices and supporting infrastructure in a secure, reproducible, and scalable way.

**Application source code is not stored here.**  
Each backend service (user-management, api-gateway, payment-service, etc.) lives in its own dedicated repository.

---

## Repository Structure

```
portable-platform-infra/
├── ansible/                    # Ansible (k3s server, agent, ngrok)
│   ├── playbook.yml           # Full setup
│   ├── playbook-k3s-only.yml  # k3s only
│   └── roles/k3s-server, k3s-agent, ngrok
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

## Deployment (k8s + ArgoCD)

**Production** : ArgoCD syncs automatically from branch `test-argocd`, path `deploy/k8s`.  
See [deploy/argocd/ARGOCD-AUTODEPLOY.md](deploy/argocd/ARGOCD-AUTODEPLOY.md).

**Manual apply** :

```bash
# Prérequis : ghcr-secret, KUBECONFIG
kubectl apply -k deploy/k8s/
# Ou avec domaine ngrok :
deploy/k8s/scripts/apply-with-ngrok-domain.sh
```

See [deploy/k8s/DEPLOYMENT.md](deploy/k8s/DEPLOYMENT.md) and [deploy/SETUP.md](deploy/SETUP.md).

---

## Security

- No secrets committed to the repository
- Secrets injected at runtime (ghcr-secret, postgres-credentials, etc.)
- Backend services internal; only API Gateway + Frontend exposed via Ingress

---

## License

Proprietary — internal platform management.

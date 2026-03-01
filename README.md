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
├── ansible/                    # Ansible roles (k3s server setup)
│   └── roles/k3s-server/
├── deploy/                     # Deployment definitions
│   ├── k8s/                   # Kubernetes manifests (k3s)
│   │   ├── base/              # Namespace
│   │   ├── infra/             # Postgres, Redis, Consul, RabbitMQ
│   │   ├── apps/              # api-gateway, frontend, user-management, etc.
│   │   ├── cronjobs/          # Disk cleanup, evicted pods cleanup
│   │   ├── DEPLOYMENT.md
│   │   ├── CHECKLIST.md
│   │   └── README.md
│   ├── local/                 # Docker Compose (local dev)
│   ├── prod/                  # Docker Compose (production)
│   ├── docs/                  # Architecture documentation (.tex, etc.)
│   └── argocd/                # ArgoCD application (optional)
├── .github/workflows/         # CI/CD pipelines
├── .env.example
└── README.md
```

---

## Responsibilities

- **Kubernetes (k3s)** : manifests, Ingress, CronJobs
- **Infrastructure** : PostgreSQL, Redis, Consul, RabbitMQ
- **CI/CD** : deployment workflows
- **Documentation** : architecture, deployment guide, checklist

---

## Deployment (k8s)

```bash
# Prérequis : ghcr-secret, KUBECONFIG pointant vers le cluster
kubectl apply -k deploy/k8s/
```

See [deploy/k8s/DEPLOYMENT.md](deploy/k8s/DEPLOYMENT.md) for prerequisites and order.

See [deploy/k8s/CHECKLIST.md](deploy/k8s/CHECKLIST.md) for missing configurations (DevOps + devs).

---

## Security

- No secrets committed to the repository
- Secrets injected at runtime (ghcr-secret, postgres-credentials, etc.)
- Backend services internal; only API Gateway + Frontend exposed via Ingress

---

## License

Proprietary — internal platform management.

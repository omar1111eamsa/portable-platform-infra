# MyApp — Infrastructure Management

This repository contains all Kubernetes manifests, Ansible playbooks, and Terraform configurations for the MyApp platform deployed on a 3-node k3s cluster.

## Repository Structure

```
portable-platform-infra/
├── ansible/          Cluster provisioning playbooks
├── terraform/        GCP base infrastructure
└── deploy/
    ├── argocd/       ArgoCD application definition
    ├── docs/         Architecture and operational documentation
    ├── k8s/          Kubernetes manifests (apps, infra, network)
    ├── SETUP.md      Full cluster bootstrap guide
    └── TESTERS-GUIDE.md  API and endpoint reference for testers
```

## Cluster Overview

| Node | Role | Internal IP |
|---|---|---|
| backend-vm | k3s control-plane | 10.0.0.11 |
| frontend-vm | k3s worker, public ingress | 10.0.0.12 |
| backend2 | k3s worker | 10.0.0.13 |

- **Namespace**: `myapp`
- **Ingress**: Traefik
- **GitOps**: ArgoCD watching `test-argocd` branch of this repository
- **Domain**: `dev.example.com`

## CI/CD Flow

Every service repository has a `test-ci` branch. On each push:

1. GitHub Actions builds and pushes a Docker image to GHCR, tagged with the commit SHA.
2. CI writes the new image tag into the corresponding deployment manifest in this repository.
3. ArgoCD detects the change and syncs the cluster automatically.

No manual manifest updates are required.

## Documentation Index

| Document | Purpose |
|---|---|
| [deploy/docs/ARCHITECTURE-K8S.md](deploy/docs/ARCHITECTURE-K8S.md) | Kubernetes architecture, node layout, workload placement |
| [deploy/docs/FLOW-END-TO-END.md](deploy/docs/FLOW-END-TO-END.md) | Full trading pipeline flow, stages and database writes |
| [deploy/docs/SERVICE-MATRIX.md](deploy/docs/SERVICE-MATRIX.md) | All services, images, ports, dependencies |
| [deploy/docs/DB-ARCHITECTURE.md](deploy/docs/DB-ARCHITECTURE.md) | Database schema, tables, relationships |
| [deploy/docs/METAMODEL-FONCTIONNEMENT.md](deploy/docs/METAMODEL-FONCTIONNEMENT.md) | Airflow DAG pipeline internals |
| [deploy/docs/ENDPOINTS-CATALOG.md](deploy/docs/ENDPOINTS-CATALOG.md) | All API endpoints |
| [deploy/SETUP.md](deploy/SETUP.md) | Cluster bootstrap from scratch |
| [deploy/TESTERS-GUIDE.md](deploy/TESTERS-GUIDE.md) | Tester reference: URLs, auth, API usage |
| [deploy/argocd/ARGOCD-AUTODEPLOY.md](deploy/argocd/ARGOCD-AUTODEPLOY.md) | ArgoCD setup and auto-deploy configuration |
| [ansible/README.md](ansible/README.md) | Ansible usage and inventory |
| [terraform/README.md](terraform/README.md) | Terraform GCP infrastructure |

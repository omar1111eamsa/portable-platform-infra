# MyApp — Portable Platform Infrastructure

Infrastructure and GitOps control plane that provisions a complete multi-service platform on a
k3s cluster — and is designed to be **fully portable**, so the same architecture can be rebuilt,
end to end, on any cloud or bare-metal host.

## The assignment

I was asked to build a **fully portable architecture**: a platform that runs *everywhere* — not
tied to a single cloud or hand-configured machine — and to **integrate all of the platform's
services** into one coherent, deployable environment where the whole system can be brought up and
seen working, not just individual pieces.

Concretely, that meant solving two problems together:

1. **Portability** — describe the entire stack (cloud resources, cluster, every service) as code,
   so it reproduces identically anywhere with no manual steps and no provider lock-in.
2. **Integration** — wire ~25 application, orchestration, and infrastructure services into a single
   running system, so the result is a working environment you can open in a browser, not a pile of
   disconnected containers.

## How portability is achieved

Three declarative layers turn nothing into the full running platform, each swappable per
environment:

| Layer | Tool | Responsibility | Portable because… |
|-------|------|----------------|-------------------|
| Cloud base | **Terraform** | VMs, network, base infra | provider module can target any cloud; nothing clicked by hand |
| Cluster | **Ansible** | k3s install + config across nodes | runs over SSH against *any* hosts — cloud or bare metal |
| Workloads | **Kubernetes + ArgoCD** | every service, declared as manifests | k3s + standard manifests run identically anywhere |

Because every layer is code, the entire platform can be torn down and rebuilt from scratch on a
different provider with no change to the application services themselves — that is the portability
the brief asked for.

## The integrated platform (~25 services)

All services run in namespace `myapp` on a 3-node k3s cluster, deployed and kept in sync by ArgoCD.

**Application services (12)** — `api-gateway` (single entry), `frontend`, `admin-frontend`,
`user-management`, `payment-service`, `chatbot`, `kpi-dashboard`, `crm-client`,
`predictions-intake`, `scoring-engine`, `portfolio-builder`, `execution-engine`.

**Orchestration (Airflow, CeleryExecutor)** — API server, scheduler, DAG processor, Celery worker,
triggerer (the data/model pipeline).

**Infrastructure (8)** — PostgreSQL, Redis, RabbitMQ, MinIO, Consul, Prometheus, Grafana, pgAdmin.

Services are integrated, not isolated: the gateway fronts the user/predictions/chatbot/payment
services; the orchestration pipeline is backed by Postgres, Redis, RabbitMQ and MinIO; metrics flow
to Prometheus/Grafana. Full dependency map in
[`deploy/docs/SERVICE-MATRIX.md`](deploy/docs/SERVICE-MATRIX.md).

## Seeing the result

Once deployed, the integrated environment is reachable through a single domain — the proof that the
services actually run together as one platform:

| URL | Surface |
|-----|---------|
| `https://dev.example.com` | Frontend |
| `https://dev.example.com/api` | API Gateway |
| `https://dashboard.example.com` | Admin frontend |
| `https://airflow.dev.example.com` | Airflow UI |
| `https://dev.example.com/argocd` | ArgoCD (deployment state) |
| `https://dev.example.com/grafana` · `/prometheus` | Observability |
| `https://dev.example.com/rabbitmq` · `/consul` · `/pgadmin` | Ops UIs |

## CI/CD — GitOps

Each service repo has a `test-ci` branch. On every push:

1. GitHub Actions builds and pushes a Docker image to GHCR, tagged with the commit SHA.
2. CI writes the new tag into the matching deployment manifest **in this repo**.
3. ArgoCD detects the change and syncs the cluster automatically — no manual manifest edits.

## Repository structure

```
.
├── terraform/        Cloud base infrastructure (provider-swappable)
├── ansible/          k3s cluster provisioning over SSH (cloud or bare metal)
└── deploy/
    ├── argocd/       ArgoCD application definitions (GitOps)
    ├── k8s/          Kubernetes manifests — apps, infra, network policies
    ├── docs/         Architecture, end-to-end flow, service & DB matrices
    ├── SETUP.md      Full cluster bootstrap guide
    └── TESTERS-GUIDE.md  API and endpoint reference
```

## Cluster overview

| Node | Role | Internal IP |
|------|------|-------------|
| backend-vm | k3s control-plane | 10.0.0.11 |
| frontend-vm | k3s worker, public ingress | 10.0.0.12 |
| backend2 | k3s worker | 10.0.0.13 |

Namespace `myapp` · Ingress via Traefik · GitOps via ArgoCD.

## Documentation

| Document | Purpose |
|----------|---------|
| [deploy/docs/ARCHITECTURE-K8S.md](deploy/docs/ARCHITECTURE-K8S.md) | Kubernetes architecture, node layout, workload placement |
| [deploy/docs/FLOW-END-TO-END.md](deploy/docs/FLOW-END-TO-END.md) | Full pipeline flow, stages and database writes |
| [deploy/docs/SERVICE-MATRIX.md](deploy/docs/SERVICE-MATRIX.md) | All services, images, ports, dependencies |
| [deploy/docs/DB-ARCHITECTURE.md](deploy/docs/DB-ARCHITECTURE.md) | Database schema, tables, relationships |
| [deploy/docs/METAMODEL-FONCTIONNEMENT.md](deploy/docs/METAMODEL-FONCTIONNEMENT.md) | Airflow DAG pipeline internals |
| [deploy/docs/ENDPOINTS-CATALOG.md](deploy/docs/ENDPOINTS-CATALOG.md) | All API endpoints |
| [deploy/SETUP.md](deploy/SETUP.md) | Cluster bootstrap from scratch |
| [deploy/TESTERS-GUIDE.md](deploy/TESTERS-GUIDE.md) | Tester reference: URLs, auth, API usage |
| [deploy/argocd/ARGOCD-AUTODEPLOY.md](deploy/argocd/ARGOCD-AUTODEPLOY.md) | ArgoCD setup and auto-deploy configuration |
| [ansible/README.md](ansible/README.md) | Ansible usage and inventory |
| [terraform/README.md](terraform/README.md) | Terraform infrastructure |

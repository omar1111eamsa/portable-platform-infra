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

## Challenges I faced (and how I solved them)

Integrating ~25 services on a self-managed cluster was where the real work was — almost none of it
worked first try. Each of these is a problem I actually hit (traceable in the commit history) and
how I resolved it:

- **Airflow behind an ingress was a fight.** The UI base path was wrong, static assets 404'd, and
  the API path was being **duplicated to `/api/v2/api/v2`**. I worked through it: corrected the UI
  base path and static routes, added a middleware to dedupe the API prefix, copied the simple-auth
  file into a **writable** volume, and removed a `chown` from init (the pod runs `runAsNonRoot`, so
  it had no permission). Airflow finally served correctly under its subdomain.
- **Stateful pods that couldn't move.** Postgres and the chatbot use `ReadWriteOnce` PVCs, so a pod
  can only run on the node holding its volume. Pinned those workloads to the correct node via node
  affinity, kept Postgres at a single replica (RWO can't be shared), and only scaled the
  truly-stateless infra (Redis/RabbitMQ/Consul) to 2.
- **Services couldn't find each other.** The API gateway resolved `user-service` inconsistently
  between Kubernetes DNS and Consul load-balancing. Standardised on the in-cluster DNS name with a
  fallback, and stabilised Consul's single-node service registration.
- **Locking the namespace down broke things — then I fixed them properly.** Added baseline network
  policies and disabled service-account token automount for hardening, then surgically re-allowed
  exactly what was needed: RabbitMQ management UI traffic, and pod-watch permission for the
  health-check service account.
- **ArgoCD stuck in permanent "OutOfSync".** A startup probe and manually scaled-down replicas kept
  showing as drift, so ArgoCD fought my changes. Added targeted `ignoreDifferences` (and
  `RespectIgnoreDifferences`) so it ignores fields I intentionally manage by hand.
- **`ImagePullBackOff` from bad image references.** A wrong/short image SHA and a missing tag stalled
  the frontend rollout. Pinned the correct tags and corrected the public API URL so the frontend
  came up.
- **Operational papercuts** — Stripe webhooks needed an explicit ingress path; cert-manager's ACME
  challenge had to be allowed on the Airflow subdomain; admin UIs (Consul, RabbitMQ) were put behind
  Traefik basic auth instead of being exposed.

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
    ├── docs/         Kubernetes architecture & service matrix
    └── SETUP.md      Full cluster bootstrap guide
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
| [deploy/docs/SERVICE-MATRIX.md](deploy/docs/SERVICE-MATRIX.md) | All services, images, ports, dependencies |
| [deploy/SETUP.md](deploy/SETUP.md) | Cluster bootstrap from scratch |
| [deploy/k8s/DEPLOYMENT.md](deploy/k8s/DEPLOYMENT.md) | Deployment prerequisites and apply order |
| [deploy/k8s/OAUTH2-FIX.md](deploy/k8s/OAUTH2-FIX.md) | Google OAuth2 fix applied to the API Gateway |
| [deploy/argocd/ARGOCD-AUTODEPLOY.md](deploy/argocd/ARGOCD-AUTODEPLOY.md) | ArgoCD setup and auto-deploy configuration |
| [ansible/README.md](ansible/README.md) | Ansible usage and inventory |
| [terraform/README.md](terraform/README.md) | Terraform infrastructure |

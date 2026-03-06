# Deploy Directory

- **`k8s/`** — Kubernetes manifests (production, used by ArgoCD). See [k8s/README.md](k8s/README.md) and [SETUP.md](SETUP.md).
- **`local/`** — Docker Compose for local development.
- **`docs/`** — Architecture and indexes. See [docs/INDEX.md](docs/INDEX.md).
- **`argocd/`** — ArgoCD Application definition (watches `test-argocd`).

---

# Local Backend Deployment

Docker Compose builds application services from source and runs infrastructure images for local development.

---

## Required repository structure

Docker Compose relies on **relative build paths**. Repositories must be structured as follows:

```
BACKEND/
├── API-GATEWAY/          # Backend-api-gateway repo
│   └── dockerfile
├── USER-SERVICE/         # Backend-User-management-and-subscripption repo
│   └── dockerfile
├── PORTABLE-PLATFORM/   # This repo
│   └── deploy/
│       └── local/
│           └── docker-compose.yml
```

---

## What Docker Compose Does

- Builds **API Gateway** and **User Service** from their Dockerfiles
- Runs official images for:
  - PostgreSQL
  - Redis
  - Consul
- Connects all services on a shared Docker network
- Enables service discovery via Consul

---

## Run Locally

From the `deploy/local` directory:

```bash
docker compose up -d --build
```

---

### Exposed Services

| Service    | URL                  |
|------------|----------------------|
| API Gateway| http://localhost:8888 |
| User Service | http://localhost:8081 |
| Consul UI  | http://localhost:8500 |


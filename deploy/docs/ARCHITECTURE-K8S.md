# Kubernetes Architecture

## Cluster Topology

Three-node k3s cluster on GCP:

| Node | Role | Internal IP | Workloads |
|---|---|---|---|
| backend-vm | control-plane | 10.0.0.11 | API Gateway, Frontend, User Management, CRM, KPI, Chatbot, Scoring Engine, Portfolio Builder |
| frontend-vm | worker, public ingress | 10.0.0.12 | Traefik, Admin Frontend, pgAdmin |
| backend2 | worker | 10.0.0.13 | Airflow (all components), Execution Engine, Predictions Intake, Payment Service |

- **Ingress controller**: Traefik (deployed by k3s)
- **Namespace**: `myapp`
- **GitOps**: ArgoCD, monitoring `test-argocd` branch

## Manifest Layout

```
deploy/k8s/
├── kustomization.yaml        Root kustomize entry point
├── base/                     Namespace definition
├── infra/                    Shared infrastructure
│   ├── postgres/
│   ├── redis/
│   ├── rabbitmq/
│   ├── minio/
│   ├── consul/
│   └── monitoring/           Prometheus, Grafana, exporters
├── apps/                     Application workloads
│   ├── api-gateway/
│   ├── frontend/
│   ├── admin-frontend/
│   ├── chatbot/
│   ├── user-management/
│   ├── payment-service/
│   ├── kpi-dashboard/
│   ├── crm-client/
│   ├── predictions-intake/
│   ├── scoring-engine/
│   ├── portfolio-builder/
│   ├── execution-engine/
│   ├── metamodel-orchestration/
│   └── pgadmin/
├── cronjobs/                 Maintenance jobs
├── network-policies/         Default-deny baseline
└── argocd/                   ArgoCD ingress
```

## Infrastructure Components

### PostgreSQL
- Single pod with 5Gi PVC on `backend2`
- Init job creates all application databases on first start
- Connection string: `postgresql://postgres:postgres@postgres:5432/<db>`

### Redis
- Used as Celery broker for Airflow CeleryExecutor
- No persistence (ephemeral cache)

### RabbitMQ
- Event bus for the trading pipeline
- Exchanges: `pipeline.events`, `execution.events`
- Exposed at `https://dev.example.com/rabbitmq`

### MinIO
- S3-compatible object store
- Used for Airflow remote task log storage
- Bucket: `airflow-logs`

### Consul
- Service registry for internal service discovery
- Exposed at `https://dev.example.com/consul` (BasicAuth protected)

## Application Workloads

### API Gateway
- Routes all external HTTP traffic to backend services
- Handles JWT validation, OAuth2 callbacks
- Public paths: `/api`, `/login`, `/oauth2`, `/chatbot`, `/payment-service`

### Airflow (Metamodel Orchestration)
- Runs in CeleryExecutor mode
- Components: `api-server`, `scheduler`, `dag-processor`, `worker`, `triggerer`
- All components on `backend2`
- Task logs stored in MinIO via S3-compatible remote logging
- DAGs and scoring modules served from `metamodel-modules-pvc`
- Exposed at `https://airflow.dev.example.com`

### Execution Engine
- Realtime RabbitMQ consumer
- Subscribes to `execution.events` / `trade_signal.created`
- Writes filled trade results to `filled_trades` table
- Runs as a Deployment (always-on, not a CronJob)

## Ingress Routing

| Path / Host | Destination |
|---|---|
| `dev.example.com/api` | api-gateway:8080 |
| `dev.example.com/login` | api-gateway:8080 |
| `dev.example.com/oauth2` | api-gateway:8080 |
| `dev.example.com/` | frontend:80 |
| `dashboard.example.com/` | admin-frontend:8080 |
| `airflow.dev.example.com/` | metamodel-orchestration:8080 |
| `dev.example.com/argocd` | argocd-server:80 (namespace argocd) |
| `dev.example.com/grafana` | grafana:3000 |
| `dev.example.com/prometheus` | prometheus:9090 |
| `dev.example.com/rabbitmq` | rabbitmq-management:15672 |
| `dev.example.com/consul` | consul:8500 |
| `dev.example.com/pgadmin` | pgadmin:80 |

## CronJobs

| Job | Schedule | Purpose |
|---|---|---|
| clean-disk-backend | `*/30 * * * *` | Disk cleanup on backend-vm |
| clean-disk-frontend | `15,45 * * * *` | Disk cleanup on frontend-vm |
| clean-evicted-pods | `*/30 * * * *` | Delete Failed/Succeeded pods in myapp namespace |
| metamodel-health-check | `*/5 * * * *` | Poll Airflow health endpoint |

## Secrets (Created Manually)

The following secrets are not versioned in this repository and must be created before deploying:

| Secret Name | Contents |
|---|---|
| `ghcr-secret` | Docker registry credentials for GHCR image pull |
| `metamodel-db-credentials` | Airflow PostgreSQL connection string |
| `metamodel-airflow-simple-auth` | Airflow UI admin password |
| `metamodel-airflow-s3-logging` | MinIO S3-compatible connection for Airflow logs |
| `minio-credentials` | MinIO root user, password, bucket name |
| `auth-credentials` | Shared JWT secret (gateway + user-management) |
| `chatbot-credentials` | LLM API key (OpenRouter) |
| `google-oauth-credentials` | Google OAuth2 client ID and secret |
| `stripe-credentials` | Stripe API keys |
| `consul-ui-basic-auth` | Traefik BasicAuth for Consul UI |
| `github-token` | GHCR pull token for module sync init container |

## Apply Order

ArgoCD applies the full stack via `kubectl apply -k deploy/k8s`. The natural kustomize resolution order is:

1. `base` — namespace
2. `infra` — postgres, redis, rabbitmq, minio, consul, monitoring
3. `apps` — all application workloads
4. `cronjobs` — maintenance jobs + RBAC
5. `argocd` — ArgoCD ingress (namespace: argocd)

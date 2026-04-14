# Service Matrix

All services deployed in namespace `myapp` on the k3s cluster.

## Application Services

| Service | Image | Port | Node | Branch |
|---|---|---|---|---|
| api-gateway | `ghcr.io/myapp/backend-api-gateway` | 8080 | frontend-vm | test-ci |
| frontend | `ghcr.io/myapp/front-end` | 80 | frontend-vm | test-ci |
| admin-frontend | `ghcr.io/myapp/admin-frontend` | 8080 | frontend-vm | test-ci |
| user-management | `ghcr.io/myapp/backend-user-management-and-subscripption` | 8081 | frontend-vm | test-ci |
| payment-service | `ghcr.io/myapp/backend-payment-service` | 8083 | backend2 | test-ci |
| chatbot | `ghcr.io/myapp/backend-chatbot` | 8085 | frontend-vm | test-ci |
| kpi-dashboard | `ghcr.io/myapp/backend-kpi-dashboard-notifications` | 8086 | frontend-vm | test-ci |
| crm-client | `ghcr.io/myapp/backend-crm-client` | 8087 | frontend-vm | test-ci |
| predictions-intake | `ghcr.io/myapp/backend-predictions-intake-service` | 8082 | backend2 | test-ci |
| scoring-engine | `ghcr.io/myapp/metamodel-scoring-engine` | — | backend2 | test-ci |
| portfolio-builder | `ghcr.io/myapp/metamodel-portfolio-builder` | — | backend2 | test-ci |
| execution-engine | `ghcr.io/myapp/cq-execution-engine` | — | backend2 | test-ci |

## Airflow Components

All Airflow components run on `backend2`, using `CeleryExecutor` with Redis as broker.

| Component | Deployment Name | Port |
|---|---|---|
| API server | metamodel-orchestration | 8080 |
| Scheduler | metamodel-scheduler | — |
| DAG processor | metamodel-dag-processor | — |
| Celery worker | metamodel-worker | — |
| Triggerer | metamodel-triggerer | — |

## Infrastructure Services

| Service | Image | Port | Persistence |
|---|---|---|---|
| postgres | postgres:15 | 5432 | 5Gi PVC |
| redis | redis:7 | 6379 | none |
| rabbitmq | rabbitmq:3-management | 5672 / 15672 | none |
| minio | minio/minio | 9000 / 9001 | 5Gi PVC |
| consul | consul:1.15 | 8500 | none |
| grafana | grafana/grafana | 3000 | none |
| prometheus | prom/prometheus | 9090 | none |
| pgadmin | dpage/pgadmin4 | 80 | none |

## Service Dependencies

| Service | Depends On |
|---|---|
| api-gateway | user-management, predictions-intake, chatbot, payment-service |
| metamodel-orchestration (all) | postgres, redis, rabbitmq, minio |
| execution-engine | rabbitmq, postgres |
| predictions-intake | postgres |
| user-management | postgres |
| payment-service | postgres |
| chatbot | (LLM API key via secret) |

## External Surfaces

| URL | Service |
|---|---|
| `https://dev.example.com` | Frontend |
| `https://dev.example.com/api` | API Gateway |
| `https://dashboard.example.com` | Admin Frontend |
| `https://airflow.dev.example.com` | Airflow UI |
| `https://dev.example.com/argocd` | ArgoCD UI |
| `https://dev.example.com/grafana` | Grafana |
| `https://dev.example.com/prometheus` | Prometheus |
| `https://dev.example.com/rabbitmq` | RabbitMQ Management |
| `https://dev.example.com/consul` | Consul UI |
| `https://dev.example.com/pgadmin` | pgAdmin |

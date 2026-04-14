# Infrastructure

Shared infrastructure components deployed in namespace `myapp`.

## Components

| Directory | Service | Purpose |
|---|---|---|
| `postgres/` | PostgreSQL 15 | Primary database for all application services. 5Gi PVC. Init job creates application databases on first start. |
| `redis/` | Redis 7 | Celery message broker for Airflow CeleryExecutor. No persistence. |
| `rabbitmq/` | RabbitMQ 3 | Event bus for the trading pipeline. Exchanges: `pipeline.events`, `execution.events`. |
| `minio/` | MinIO | S3-compatible object store for Airflow remote task logs. 5Gi PVC. Init job creates the `airflow-logs` bucket. |
| `consul/` | Consul | Service registry. Exposed at `/consul` with BasicAuth. |
| `monitoring/` | Prometheus + Grafana | Metrics collection and dashboards. StatSD exporter for Airflow metrics. Postgres exporter for DB metrics. |

## Notes

- All infrastructure runs on `backend2` except MinIO (also on `backend2`) and Consul (frontend-vm).
- PostgreSQL and MinIO use `hostPath`-backed PVCs bound by `nodeSelector` to their respective nodes.
- RabbitMQ and Redis have no persistence — they recover from the Airflow scheduler and broker on restart.

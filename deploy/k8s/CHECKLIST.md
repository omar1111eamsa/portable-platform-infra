# Configuration Backlog

Items that remain to be hardened before a production deployment. This file is a backlog only — it does not reflect the current deployed state. For the deployed state, refer to `deploy/docs/ARCHITECTURE-K8S.md`.

## Security

- [ ] Replace self-signed TLS with Let's Encrypt certificates for all ingress routes
- [ ] Rotate all default passwords (PostgreSQL, MinIO, RabbitMQ, Consul BasicAuth)
- [ ] Move all secrets to an external secrets manager (e.g., Vault, GCP Secret Manager)
- [ ] Restrict network policies to service-level allow-lists instead of broad port ranges
- [ ] Enable RabbitMQ authentication with dedicated users per service
- [ ] Audit RBAC roles — apply principle of least privilege to all ServiceAccounts

## Reliability

- [ ] Add pod disruption budgets for critical services (api-gateway, user-management, execution-engine)
- [ ] Add horizontal pod autoscaling for API Gateway and predictions-intake
- [ ] Configure PostgreSQL with a replica or backup strategy (currently single-instance)
- [ ] Configure MinIO with multi-drive or replication (currently single-instance)
- [ ] Add liveness and readiness probes to services that currently lack them

## Observability

- [ ] Configure Grafana dashboards for pipeline stage latency and throughput
- [ ] Add alerting rules in Prometheus for pod crash loops, disk pressure, and failed DAG runs
- [ ] Enable Airflow metrics export to StatsD exporter (already deployed, wiring pending)

## CI/CD

- [ ] Add integration test jobs to GitHub Actions CI pipelines
- [ ] Add automatic rollback on health check failure after ArgoCD sync

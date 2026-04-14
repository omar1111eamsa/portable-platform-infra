# Metamodel Orchestration — Operations Guide

## Architecture

Airflow runs in CeleryExecutor mode with five separate deployments:

| Deployment | Role |
|---|---|
| metamodel-orchestration | Airflow API server (UI + REST API) |
| metamodel-scheduler | DAG scheduler |
| metamodel-dag-processor | DAG file processor |
| metamodel-worker | Celery task worker |
| metamodel-triggerer | Deferrable operator triggerer |

All components share the same container image and run on `backend2`.

## Persistent Storage

- `metamodel-modules-pvc` — mounted at `/opt/airflow/modules` in all pods. Contains DAG files and Python scoring/portfolio modules. Changes to files on this PVC take effect on the next DAG run without requiring a pod restart or image rebuild.
- MinIO — used for remote task log storage. Airflow writes logs to `s3://airflow-logs/` via the `aws_default` connection pointing to the internal MinIO service.

## Module Loading

The `cq-scoring` and `cq-portfolio` modules are loaded from `/opt/airflow/modules` at DAG runtime. They are synced from GitHub via an init container on pod startup using the `github-token` secret. To update modules without redeploying the pod, copy files directly to the PVC mount on `backend2`.

## Required Secrets

All secrets must exist in namespace `myapp` before deployment:

| Secret | Keys |
|---|---|
| metamodel-db-credentials | `DB_CONN`, `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` |
| metamodel-airflow-simple-auth | `AIRFLOW_ADMIN_PASSWORD` |
| metamodel-airflow-s3-logging | `AIRFLOW_CONN_AWS_DEFAULT` |
| minio-credentials | `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` |
| auth-credentials | `JWT_SECRET` |
| github-token | `GITHUB_TOKEN` |
| ghcr-secret | Docker registry pull credentials |

## Operational Commands

```bash
# Pod status
kubectl -n myapp get pods -l app=metamodel-orchestration
kubectl -n myapp get pods -l app=metamodel-scheduler
kubectl -n myapp get pods -l app=metamodel-worker

# Airflow health
kubectl -n myapp exec deploy/metamodel-orchestration -- \
  curl -s http://127.0.0.1:8080/api/v2/monitor/health | python3 -m json.tool

# List DAGs
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags list

# Trigger a run manually
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags trigger metapipeline_dag

# View recent DAG runs
kubectl -n myapp exec deploy/metamodel-orchestration -- \
  airflow dags list-runs metapipeline_dag

# Check task states for a specific run
kubectl -n myapp exec deploy/metamodel-orchestration -- \
  airflow tasks states-for-dag-run metapipeline_dag <run_id>
```

## Troubleshooting

| Symptom | Action |
|---|---|
| DAG not visible in UI | Check `metamodel-dag-processor` logs for import errors |
| Task stuck in queued state | Check `metamodel-worker` is running and Redis is reachable |
| Logs not loading in UI | Verify `minio-init-airflow-logs` job completed and `aws_default` connection is set |
| Module import error | Check `/opt/airflow/modules` content on PVC; re-run init container if needed |

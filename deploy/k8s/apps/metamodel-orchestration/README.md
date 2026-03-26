# Metamodel Orchestration (Airflow)

Airflow runs with 5 workloads on `backend2`:
- `metamodel-orchestration` (API server, port 8080)
- `metamodel-scheduler` (scheduler)
- `metamodel-dag-processor` (DAG parser for Airflow 3)
- `metamodel-worker` (Celery worker)
- `metamodel-triggerer` (Triggerer)

Executor mode is `CeleryExecutor` with Redis broker (`redis://redis:6379/0`).

Metadata DB is PostgreSQL (`AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` from secret `metamodel-db-credentials` key `AIRFLOW_CONN_POSTGRES_MYAPP`).

The code modules are mounted from PVC `metamodel-modules-pvc` at `/opt/airflow/modules`.

Mounted source modules in the running Airflow pods:
- `metamodel-scoring-engine-new` -> `/opt/airflow/modules/cq-scoring`
- `Metamodel-portfolio-builder` -> `/opt/airflow/modules/cq-portfolio`

These repos are cloned by the `modules-sync` init container into the shared PVC, then reused by the API server, scheduler, worker, dag-processor, and triggerer through `PYTHONPATH`.

## Temporary UI exposure

Airflow UI is exposed temporarily through Traefik on:

```text
http://airflow.dev.example.com
```

This assumes DNS for `airflow.dev.example.com` points to the same ingress entrypoint as the rest of the dev environment.

The current auth mode is Airflow SimpleAuth for dev. The admin password is mounted from the Kubernetes secret `metamodel-airflow-simple-auth` at `/opt/airflow/secrets/simple_auth_manager_passwords.json`, so it remains stable across pod restarts and image updates until the secret is rotated.

## Operational checks

```bash
kubectl -n myapp get deploy metamodel-orchestration metamodel-scheduler metamodel-dag-processor metamodel-worker metamodel-triggerer
kubectl -n myapp get pods -l app=metamodel-orchestration
kubectl -n myapp get pods -l app=metamodel-scheduler
kubectl -n myapp get pods -l app=metamodel-dag-processor
kubectl -n myapp get pods -l app=metamodel-worker
kubectl -n myapp get pods -l app=metamodel-triggerer
```

Health check from API pod:

```bash
kubectl -n myapp exec deploy/metamodel-orchestration -- \
  python3 - <<'PY'
import urllib.request
u="http://127.0.0.1:8080/api/v2/monitor/health"
with urllib.request.urlopen(u, timeout=10) as r:
    print(r.status)
    print(r.read().decode())
PY
```

Expected:
- `metadatabase=healthy`
- `scheduler=healthy`
- `triggerer=healthy`
- `dag_processor=healthy`

Automatic monitoring is also deployed through `deploy/k8s/cronjobs/metamodel-health-check.yaml`. It checks the same endpoint through the internal service URL instead of `kubectl exec`.

## DAG test run

Current DAG split:
- `metapipeline_dag`: Stage A, every 5 minutes
- `stage_b_dag`: Stage B + reward, every hour

```bash
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags list
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags unpause metapipeline_dag
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags unpause stage_b_dag
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags trigger metapipeline_dag
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags list-runs metapipeline_dag
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags list-runs stage_b_dag
```

Timing note:
- Stage B respects the `1h` horizon logic, but runs in batch mode on the next hourly `stage_b_dag` schedule.
- A prediction inserted manually can be consumed by a waiting scheduled Stage A run before a manual run reaches `task_score`.

## Current dev validation

The current dev deployment has been revalidated for Stage A end to end:
- new prediction detected
- scoring succeeded
- portfolio succeeded
- trade signal created
- execution verification succeeded

Stage B is deployed separately and has successful runs, but should be validated as its own path after the 1-hour horizon has elapsed.

## Disk pressure recovery (backend2)

```bash
sudo k3s crictl rmi --prune
kubectl describe node backend2 | grep -A5 Conditions
```

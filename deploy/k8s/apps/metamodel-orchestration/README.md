# Metamodel Orchestration (Airflow)

Airflow runs with 3 workloads on `backend2`:
- `metamodel-orchestration` (API server, port 8080)
- `metamodel-scheduler` (scheduler)
- `metamodel-dag-processor` (DAG parser for Airflow 3)

Metadata DB is PostgreSQL (`AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` from secret `metamodel-db-credentials` key `AIRFLOW_CONN_POSTGRES_MYAPP`).

The code modules are mounted from PVC `metamodel-modules-pvc` at `/opt/airflow/modules`.

## Operational checks

```bash
kubectl -n myapp get deploy metamodel-orchestration metamodel-scheduler metamodel-dag-processor
kubectl -n myapp get pods -l app=metamodel-orchestration
kubectl -n myapp get pods -l app=metamodel-scheduler
kubectl -n myapp get pods -l app=metamodel-dag-processor
```

Health check from API pod:

```bash
kubectl -n myapp exec deploy/metamodel-orchestration -- \
  python - <<'PY'
import urllib.request
u="http://127.0.0.1:8080/api/v2/monitor/health"
with urllib.request.urlopen(u, timeout=10) as r:
    print(r.status)
    print(r.read().decode())
PY
```

Expected: `metadatabase=healthy` and `scheduler=healthy`.

## DAG test run

```bash
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags list
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags unpause metapipeline_dag
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags trigger metapipeline_dag
kubectl -n myapp exec deploy/metamodel-orchestration -- airflow dags list-runs -d metapipeline_dag
```

## Disk pressure recovery (backend2)

```bash
sudo k3s crictl rmi --prune
kubectl describe node backend2 | grep -A5 Conditions
```

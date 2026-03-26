# Infra Folder Guide

This folder contains only Kubernetes runtime manifests for shared infrastructure in namespace `myapp`.

## Included Infra

- `postgres/`: PVC, Deployment, Service, init job for app databases
- `minio/`: PVC, Deployment, Service, init job for Airflow remote log bucket
- `redis/`: Deployment, Service
- `consul/`: Deployment, Service
- `rabbitmq/`: definitions configmap, Deployment, Service

Everything deployed from this folder is referenced by [`kustomization.yaml`](./kustomization.yaml).

## Secrets Policy

Secret examples were removed from this folder to avoid duplicated docs.
Use the canonical commands in:

- [`../DEPLOYMENT.md`](../DEPLOYMENT.md)
- [`../CHECKLIST.md`](../CHECKLIST.md)

Required secrets for infra/app boot:

- `postgres-credentials`
- `minio-credentials`
- `metamodel-airflow-s3-logging`
- `rabbitmq-credentials`
- `ghcr-secret`

## Deploy / Verify

```bash
kubectl apply -k deploy/k8s/infra/
kubectl -n myapp get deploy postgres redis consul rabbitmq minio
kubectl -n myapp get jobs minio-init-airflow-logs
kubectl -n myapp get pods | rg -i 'postgres|redis|consul|rabbitmq|minio'
```

## Notes

- `postgres/init-databases-job.yaml` creates app databases (`payment_db`, `crm_db`, `prediction_db`, `kpi_db`) and is kept in this folder because it is part of infra bootstrap.
- `minio/init-bucket-job.yaml` creates bucket `airflow-logs` for Airflow remote logging.
- Do not add app-specific manifests here; place them under `deploy/k8s/apps/`.

# Deployment — Prerequisites and Apply Order

## Cluster Requirements

Three k3s nodes must be provisioned. Node names must match exactly:

| Node | IP | Role |
|---|---|---|
| backend-vm | 10.0.0.11 | k3s control-plane |
| frontend-vm | 10.0.0.12 | k3s worker + public ingress |
| backend2 | 10.0.0.13 | k3s worker |

k3s version: v1.35 or later. Traefik is installed automatically by k3s.

## Secrets — Create Before Applying

The following secrets must be created manually before running `kubectl apply`. They are not stored in this repository.

```bash
# GHCR image pull secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<github_user> \
  --docker-password=<github_pat> \
  -n myapp

# PostgreSQL + Airflow metadata
kubectl create secret generic metamodel-db-credentials \
  --from-literal=DB_CONN=postgresql://postgres:postgres@postgres:5432/prediction_db \
  --from-literal=AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://postgres:postgres@postgres:5432/airflow \
  -n myapp

# Airflow UI password
kubectl create secret generic metamodel-airflow-simple-auth \
  --from-literal=AIRFLOW_ADMIN_PASSWORD=<password> \
  -n myapp

# MinIO credentials
kubectl create secret generic minio-credentials \
  --from-literal=MINIO_ROOT_USER=minioadmin \
  --from-literal=MINIO_ROOT_PASSWORD=<password> \
  --from-literal=AIRFLOW_LOGS_BUCKET=airflow-logs \
  -n myapp

# Airflow S3 remote logging (points to MinIO)
kubectl create secret generic metamodel-airflow-s3-logging \
  --from-literal=AIRFLOW_CONN_AWS_DEFAULT='aws://?endpoint_url=http%3A%2F%2Fminio.myapp.svc.cluster.local%3A9000&aws_access_key_id=minioadmin&aws_secret_access_key=<password>' \
  -n myapp

# Shared JWT secret
kubectl create secret generic auth-credentials \
  --from-literal=JWT_SECRET=<jwt_secret> \
  -n myapp

# Google OAuth2
kubectl create secret generic google-oauth-credentials \
  --from-literal=GOOGLE_CLIENT_ID=<id> \
  --from-literal=GOOGLE_CLIENT_SECRET=<secret> \
  -n myapp

# GitHub token for module sync
kubectl create secret generic github-token \
  --from-literal=GITHUB_TOKEN=<pat> \
  -n myapp

# Chatbot LLM key
kubectl create secret generic chatbot-credentials \
  --from-literal=LLM_API_KEY=<openrouter_key> \
  -n myapp

# Consul BasicAuth
htpasswd -nb admin <password> | base64  # use output below
kubectl create secret generic consul-ui-basic-auth \
  --from-literal=users=<htpasswd_base64> \
  -n myapp
```

## Apply

```bash
kubectl apply -k deploy/k8s
```

ArgoCD handles this automatically on every push to `test-argocd`. Manual apply is only needed for bootstrap.

## Verify

```bash
# All pods running
kubectl get pods -n myapp

# Airflow health
kubectl -n myapp exec deploy/metamodel-orchestration -- \
  curl -s http://127.0.0.1:8080/api/v2/monitor/health

# Database tables accessible
kubectl exec -n myapp deploy/postgres -- \
  psql -U postgres -d prediction_db -c "\dt"
```

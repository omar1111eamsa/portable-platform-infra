#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
DEPLOY_DIR="${ROOT_DIR}/deploy/k8s"

TERRAFORM_DIR="${ROOT_DIR}/terraform"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory.generated.yml"
SECRETS_FILE="${DEPLOY_DIR}/secrets.env"
KUBECONFIG_FILE="${HOME}/.kube/myapp-k3s.yaml"
SSH_USER="${SSH_USER:-myapp}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/myapp_vms}"
SKIP_APPLY=0

usage() {
  cat <<'EOF'
Usage:
  ./ansible/bootstrap-cluster.sh [options]

Options:
  --terraform-dir <path>   Terraform directory (default: ./terraform)
  --inventory <path>       Generated Ansible inventory path
  --secrets-file <path>    Secrets env file for Kubernetes (default: deploy/k8s/secrets.env)
  --kubeconfig <path>      Output kubeconfig path (default: ~/.kube/myapp-k3s.yaml)
  --skip-apply             Only install k3s + kubeconfig/tunnel, skip secrets+kubectl apply
  -h, --help               Show this help

Before full bootstrap:
  cp deploy/k8s/secrets.env.example deploy/k8s/secrets.env
  # fill real values in deploy/k8s/secrets.env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --inventory)
      INVENTORY_FILE="$2"
      shift 2
      ;;
    --secrets-file)
      SECRETS_FILE="$2"
      shift 2
      ;;
    --kubeconfig)
      KUBECONFIG_FILE="$2"
      shift 2
      ;;
    --skip-apply)
      SKIP_APPLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
}

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required variable in secrets file: $key"
    exit 1
  fi
}

create_or_update_secret() {
  local name="$1"
  shift
  kubectl -n myapp create secret generic "$name" "$@" --dry-run=client -o yaml | kubectl apply -f -
}

require_cmd terraform
require_cmd ansible-playbook
require_cmd ssh
require_cmd kubectl
require_cmd openssl

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key not found: ${SSH_KEY}"
  exit 1
fi

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
  echo "Terraform dir not found: ${TERRAFORM_DIR}"
  exit 1
fi

echo "[1/7] Generate Ansible inventory from Terraform outputs"
"${ANSIBLE_DIR}/render-inventory.sh" "${TERRAFORM_DIR}" "${INVENTORY_FILE}"

echo "[2/7] Install/repair k3s cluster with Ansible"
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "${INVENTORY_FILE}" "${ANSIBLE_DIR}/playbook.yml"

frontend_public_ip="$(terraform -chdir="${TERRAFORM_DIR}" output -raw frontend_public_ip)"
backend_private_ip="$(terraform -chdir="${TERRAFORM_DIR}" output -raw backend_vm_private_ip)"

echo "[3/7] Pull kubeconfig from backend-vm"
mkdir -p "$(dirname "${KUBECONFIG_FILE}")"
tmp_kubeconfig="$(mktemp)"
# Reset stale host keys after VM recreation to avoid SSH key mismatch issues.
ssh-keygen -R "${frontend_public_ip}" >/dev/null 2>&1 || true
ssh-keygen -R "${backend_private_ip}" >/dev/null 2>&1 || true
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY}" \
  -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null \
  -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -i ${SSH_KEY} ${SSH_USER}@${frontend_public_ip}" \
  "${SSH_USER}@${backend_private_ip}" \
  "sudo cat /etc/rancher/k3s/k3s.yaml" > "${tmp_kubeconfig}"

sed -E 's#server: https://[^[:space:]]+:6443#server: https://127.0.0.1:16443#' \
  "${tmp_kubeconfig}" > "${KUBECONFIG_FILE}"
chmod 600 "${KUBECONFIG_FILE}"
rm -f "${tmp_kubeconfig}"

echo "[4/7] Start kubectl tunnel"
JUMP_HOST="${frontend_public_ip}" \
BACKEND_HOST="${backend_private_ip}" \
SSH_USER="${SSH_USER}" \
SSH_KEY="${SSH_KEY}" \
  "${DEPLOY_DIR}/scripts/start-kubectl-tunnel.sh" --background

export KUBECONFIG="${KUBECONFIG_FILE}"
for _ in {1..12}; do
  if kubectl --request-timeout=8s get nodes >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
if ! kubectl --request-timeout=12s get nodes >/dev/null 2>&1; then
  echo "kubectl cannot reach the cluster API after tunnel setup"
  exit 1
fi

if [[ "${SKIP_APPLY}" -eq 1 ]]; then
  echo "Bootstrap finished (cluster ready, apply skipped by --skip-apply)."
  exit 0
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "Secrets file not found: ${SECRETS_FILE}"
  echo "Create it from template: cp ${DEPLOY_DIR}/secrets.env.example ${SECRETS_FILE}"
  exit 1
fi

echo "[5/7] Apply base namespace"
kubectl apply -k "${DEPLOY_DIR}/base"

echo "[6/7] Create/update required Kubernetes secrets"
set -a
source "${SECRETS_FILE}"
set +a

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-userdb}"
RABBITMQ_DEFAULT_VHOST="${RABBITMQ_DEFAULT_VHOST:-/}"
RABBITMQ_VHOST="${RABBITMQ_VHOST:-/}"
RABBITMQ_USERNAME="${RABBITMQ_USERNAME:-${RABBITMQ_DEFAULT_USER:-}}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-${RABBITMQ_DEFAULT_PASS:-}}"
RABBITMQ_ADDRESSES="${RABBITMQ_ADDRESSES:-amqp://${RABBITMQ_USERNAME}:${RABBITMQ_PASSWORD}@rabbitmq:5672/}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin123}"
AIRFLOW_LOGS_BUCKET="${AIRFLOW_LOGS_BUCKET:-airflow-logs}"
AIRFLOW_CONN_AWS_DEFAULT="${AIRFLOW_CONN_AWS_DEFAULT:-aws://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@/?endpoint_url=http%3A%2F%2Fminio%3A9000&region_name=us-east-1}"
AIRFLOW_ADMIN_PASSWORD="${AIRFLOW_ADMIN_PASSWORD:-ChangeMeNow123!}"
PGADMIN_DEFAULT_EMAIL="${PGADMIN_DEFAULT_EMAIL:-admin@example.com}"
PGADMIN_DEFAULT_PASSWORD="${PGADMIN_DEFAULT_PASSWORD:-ChangeMeNow123!}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-ChangeMeGrafana123!}"
CONSUL_UI_USERNAME="${CONSUL_UI_USERNAME:-admin}"
CONSUL_UI_PASSWORD="${CONSUL_UI_PASSWORD:-}"

require_env GHCR_USERNAME
require_env GHCR_PASSWORD
require_env POSTGRES_PASSWORD
require_env RABBITMQ_DEFAULT_USER
require_env RABBITMQ_DEFAULT_PASS
require_env JWT_SECRET
require_env GOOGLE_CLIENT_ID
require_env GOOGLE_CLIENT_SECRET
require_env GOOGLE_REDIRECT_URI
require_env FRONTEND_URL
require_env SPRING_MAIL_USERNAME
require_env SPRING_MAIL_PASSWORD
require_env STRIPE_API_KEY
require_env STRIPE_WEBHOOK_SECRET
require_env GITHUB_TOKEN
require_env CONSUL_UI_PASSWORD

MYAPP_DB_URL="${MYAPP_DB_URL:-postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/prediction_db}"
AIRFLOW_CONN_POSTGRES_MYAPP="${AIRFLOW_CONN_POSTGRES_MYAPP:-${MYAPP_DB_URL}}"
if [[ -z "${LLM_API_KEY:-}" ]]; then
  LLM_API_KEY="sk-or-REDACTED"
  echo "WARN: LLM_API_KEY is empty, using fallback value for chatbot-credentials"
fi

kubectl -n myapp create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USERNAME}" \
  --docker-password="${GHCR_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

create_or_update_secret postgres-credentials \
  --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB="${POSTGRES_DB}"

create_or_update_secret rabbitmq-credentials \
  --from-literal=RABBITMQ_DEFAULT_USER="${RABBITMQ_DEFAULT_USER}" \
  --from-literal=RABBITMQ_DEFAULT_PASS="${RABBITMQ_DEFAULT_PASS}" \
  --from-literal=RABBITMQ_DEFAULT_VHOST="${RABBITMQ_DEFAULT_VHOST}" \
  --from-literal=RABBITMQ_USERNAME="${RABBITMQ_USERNAME}" \
  --from-literal=RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD}" \
  --from-literal=RABBITMQ_VHOST="${RABBITMQ_VHOST}" \
  --from-literal=RABBITMQ_ADDRESSES="${RABBITMQ_ADDRESSES}"

create_or_update_secret chatbot-credentials \
  --from-literal=LLM_API_KEY="${LLM_API_KEY}"

create_or_update_secret auth-credentials \
  --from-literal=JWT_SECRET="${JWT_SECRET}"

create_or_update_secret google-oauth-credentials \
  --from-literal=GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}" \
  --from-literal=GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET}" \
  --from-literal=GOOGLE_REDIRECT_URI="${GOOGLE_REDIRECT_URI}" \
  --from-literal=FRONTEND_URL="${FRONTEND_URL}"

create_or_update_secret mail-credentials \
  --from-literal=SPRING_MAIL_USERNAME="${SPRING_MAIL_USERNAME}" \
  --from-literal=SPRING_MAIL_PASSWORD="${SPRING_MAIL_PASSWORD}"

create_or_update_secret stripe-credentials \
  --from-literal=STRIPE_API_KEY="${STRIPE_API_KEY}" \
  --from-literal=STRIPE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET}"

create_or_update_secret metamodel-db-credentials \
  --from-literal=MYAPP_DB_URL="${MYAPP_DB_URL}" \
  --from-literal=AIRFLOW_CONN_POSTGRES_MYAPP="${AIRFLOW_CONN_POSTGRES_MYAPP}"

create_or_update_secret minio-credentials \
  --from-literal=MINIO_ROOT_USER="${MINIO_ROOT_USER}" \
  --from-literal=MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
  --from-literal=AIRFLOW_LOGS_BUCKET="${AIRFLOW_LOGS_BUCKET}"

create_or_update_secret metamodel-airflow-s3-logging \
  --from-literal=AIRFLOW_CONN_AWS_DEFAULT="${AIRFLOW_CONN_AWS_DEFAULT}"

tmp_auth_file="$(mktemp)"
printf '{"admin":"%s"}' "${AIRFLOW_ADMIN_PASSWORD}" > "${tmp_auth_file}"
kubectl -n myapp create secret generic metamodel-airflow-simple-auth \
  --from-file=simple_auth_manager_passwords.json="${tmp_auth_file}" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "${tmp_auth_file}"

create_or_update_secret pgadmin-credentials \
  --from-literal=PGADMIN_DEFAULT_EMAIL="${PGADMIN_DEFAULT_EMAIL}" \
  --from-literal=PGADMIN_DEFAULT_PASSWORD="${PGADMIN_DEFAULT_PASSWORD}"

create_or_update_secret grafana-admin-credentials \
  --from-literal=GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER}" \
  --from-literal=GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}"

CONSUL_UI_HASH="$(openssl passwd -apr1 "${CONSUL_UI_PASSWORD}")"
create_or_update_secret consul-ui-basic-auth \
  --from-literal=users="${CONSUL_UI_USERNAME}:${CONSUL_UI_HASH}"

create_or_update_secret github-token \
  --from-literal=token="${GITHUB_TOKEN}"

if [[ -n "${BINANCE_API_KEY:-}" && -n "${BINANCE_SECRET_KEY:-}" ]]; then
  create_or_update_secret execution-engine-broker-credentials \
    --from-literal=BINANCE_API_KEY="${BINANCE_API_KEY}" \
    --from-literal=BINANCE_SECRET_KEY="${BINANCE_SECRET_KEY}"
fi

if [[ -n "${WORLDMONITOR_BASE_URL:-}" || -n "${WORLDMONITOR_TOKEN:-}" ]]; then
  create_or_update_secret worldmonitor-credentials \
    --from-literal=WORLDMONITOR_BASE_URL="${WORLDMONITOR_BASE_URL:-}" \
    --from-literal=WORLDMONITOR_TOKEN="${WORLDMONITOR_TOKEN:-}" \
    --from-literal=WORLDMONITOR_ENDPOINT_SIGNALS="${WORLDMONITOR_ENDPOINT_SIGNALS:-/signals}" \
    --from-literal=WORLDMONITOR_TIMEOUT_SECONDS="${WORLDMONITOR_TIMEOUT_SECONDS:-10}"
fi

echo "[7/7] Apply Kubernetes stack (includes Argo CD install + Ingress)"
# Ensure argocd namespace exists before applying the full kustomize tree.
# Some kubectl/kustomize runs can try namespace-scoped Argo resources before
# creating the namespace from bundled manifests.
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k "${DEPLOY_DIR}"

# Fixed data.url in argocd-cm breaks the UI (blank page) when you open Argo CD via http://IP/argocd or a host
# that does not match that URL — remove it so the SPA uses the browser's current origin.
if kubectl get configmap argocd-cm -n argocd >/dev/null 2>&1; then
  if kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.url}' 2>/dev/null | grep -q .; then
    kubectl patch configmap argocd-cm -n argocd --type=json -p='[{"op":"remove","path":"/data/url"}]' || true
  fi
fi

# Pick up argocd-cmd-params-cm (Traefik /argocd) after first install or CM change
if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
  kubectl rollout restart deployment/argocd-server -n argocd || true
  kubectl rollout status deployment/argocd-server -n argocd --timeout=300s || true
fi

# Application CRD must exist before applying the myapp Application
for _ in $(seq 1 90); do
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s 2>/dev/null || true

# Argo CD repo-server: clone private portable-platform-infra (same token as myapp/github-token)
echo "Argo CD: register Git credentials for portable-platform-infra"
kubectl -n argocd create secret generic repo-portable-platform-infra \
  --from-literal=name=portable-platform-infra \
  --from-literal=type=git \
  --from-literal=url=https://github.com/MyApp/portable-platform-infra.git \
  --from-literal=username=x-access-token \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret repo-portable-platform-infra -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite

kubectl apply -f "${ROOT_DIR}/deploy/argocd/application-myapp.yaml"

echo "Bootstrap complete."
echo "KUBECONFIG=${KUBECONFIG_FILE}"

#!/usr/bin/env bash
# One-shot: create Argo CD repository Secret from GITHUB_TOKEN (fixes ComparisonError on private repo).
# Usage:
#   export GITHUB_TOKEN=ghp_xxx
#   ./deploy/argocd/sync-repo-secret.sh
# Or:   SECRETS_FILE=deploy/k8s/secrets.env ./deploy/argocd/sync-repo-secret.sh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_FILE="${SECRETS_FILE:-${ROOT_DIR}/deploy/k8s/secrets.env}"
if [[ -z "${GITHUB_TOKEN:-}" && -f "${SECRETS_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${SECRETS_FILE}"
  set +a
fi
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Missing GITHUB_TOKEN. Export it or set SECRETS_FILE to deploy/k8s/secrets.env"
  exit 1
fi

kubectl -n argocd create secret generic repo-portable-platform-infra \
  --from-literal=name=portable-platform-infra \
  --from-literal=type=git \
  --from-literal=url=https://github.com/MyApp/portable-platform-infra.git \
  --from-literal=username=x-access-token \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret repo-portable-platform-infra -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite

echo "Done. Hard-refresh the myapp app in Argo CD or run:"
echo "  kubectl -n argocd patch application myapp --type merge -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}'"

#!/bin/bash
# Récupère le domaine ngrok depuis l'API (sur frontend-vm) et applique les manifests k8s avec ce domaine.
# Usage: export KUBECONFIG=~/.kube/myapp-k3s.yaml; ./apply-with-ngrok-domain.sh [--domain DOMAIN]
# Si --domain non fourni, fetch depuis ngrok API sur frontend-vm (nécessite ngrok actif).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Même config SSH que start-kubectl-tunnel.sh
# Frontend = hôte avec ngrok (IP publique)
FRONTEND_HOST="${FRONTEND_HOST:-203.0.113.11}"
SSH_USER="${SSH_USER:-hodeconlimited}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/myapp_vms}"
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-i "$SSH_KEY") || SSH_OPTS=()

# Domaine par défaut (backup si fetch échoue)
DEFAULT_DOMAIN="example.ngrok-free.app"

if [[ "${1:-}" == "--domain" && -n "${2:-}" ]]; then
  NGROK_DOMAIN="$2"
  shift 2
else
  echo "Fetching ngrok domain from frontend-vm (curl http://127.0.0.1:4040/api/tunnels)..."
  NGROK_DOMAIN=$(ssh "${SSH_OPTS[@]}" -o StrictHostKeyChecking=no "${SSH_USER}@${FRONTEND_HOST}" \
    'curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -oP "(?<=\"public_url\":\")https?://[^\"]+" | head -1' 2>/dev/null | sed 's|https\?://||' || true)
  if [[ -z "$NGROK_DOMAIN" ]]; then
    echo "Could not fetch ngrok domain. Using default: $DEFAULT_DOMAIN"
    echo "Override with: ./apply-with-ngrok-domain.sh --domain your-subdomain.ngrok-free.app"
    NGROK_DOMAIN="$DEFAULT_DOMAIN"
  else
    echo "Using ngrok domain: $NGROK_DOMAIN"
  fi
fi

# Appliquer avec remplacement du domaine dans tous les manifests
echo "Building kustomize and applying with NGROK_DOMAIN=$NGROK_DOMAIN..."
kubectl kustomize "$K8S_DIR" 2>/dev/null || kustomize build "$K8S_DIR" 2>/dev/null | \
  sed "s/c4b0-203-0-113-10\.ngrok-free\.app/${NGROK_DOMAIN}/g" | \
  kubectl apply -f -

echo "Done. Frontend: https://${NGROK_DOMAIN}/  API: https://${NGROK_DOMAIN}/api"

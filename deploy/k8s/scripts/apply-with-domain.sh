#!/bin/bash
# Apply k8s manifests (domain is fixed: dev.example.com, dev.example.com)
# Usage: export KUBECONFIG=~/.kube/myapp-k3s.yaml; ./apply-with-domain.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Applying k8s manifests (dev.example.com, dev.example.com)..."
kubectl apply -k "$K8S_DIR"

echo "Done. Frontend: https://dev.example.com/  API: https://dev.example.com/  ArgoCD: https://dev.example.com/argocd"

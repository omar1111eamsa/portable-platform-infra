#!/bin/bash
# Démarrer le tunnel SSH pour accéder au cluster via kubectl
# Usage: ./start-kubectl-tunnel.sh
# Prérequis: KUBECONFIG=~/.kube/myapp-k3s.yaml (pointe sur 127.0.0.1:16443)

set -e
TUNNEL="16443:127.0.0.1:6443"
KEY="${HOME}/.ssh/myapp_vms"
JUMP="hodeconlimited@203.0.113.10"
TARGET="hodeconlimited@10.0.0.11"

# Arrêter un tunnel existant
pkill -f "ssh.*${TUNNEL}" 2>/dev/null || true
sleep 1

echo "Starting tunnel 127.0.0.1:16443 -> ${TARGET}:6443 ..."
ssh -f -N -L "${TUNNEL}" \
  -i "${KEY}" \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=30 \
  -J "${JUMP}" \
  "${TARGET}"

echo "Tunnel started. Test: kubectl get nodes"
export KUBECONFIG=~/.kube/myapp-k3s.yaml
kubectl get nodes 2>/dev/null || echo "Run: export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes"

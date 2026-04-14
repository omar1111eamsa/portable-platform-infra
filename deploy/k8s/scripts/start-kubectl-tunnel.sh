#!/bin/bash
# Tunnel kubectl vers le cluster k3s via SSH (port-forward 6443).
# Usage: ./start-kubectl-tunnel.sh [--background] [--check-vm]
# Prérequis: SSH configuré (ProxyJump via frontend-vm), KUBECONFIG=~/.kube/myapp-k3s.yaml
set -e

LOCAL_PORT="${LOCAL_PORT:-16443}"
REMOTE_PORT=6443

# SSH: jump via frontend (IP publique) → backend (réseau interne)
JUMP_HOST="${JUMP_HOST:-203.0.113.11}"
BACKEND_HOST="${BACKEND_HOST:-10.0.0.11}"
SSH_USER="${SSH_USER:-myapp}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/myapp_vms}"
SSH_OPTS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "GlobalKnownHostsFile=/dev/null" -o "ConnectTimeout=10")

[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

# ProxyCommand via jump host (more robust when host keys drift after VM recreation)
PROXY_CMD="ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -i ${SSH_KEY} ${SSH_USER}@${JUMP_HOST}"

# Option: vérifier/démarrer k3s sur backend-vm
if [[ "${1:-}" == "--check-vm" ]]; then
  shift
  echo "Checking k3s on backend via SSH..."
  ssh "${SSH_OPTS[@]}" -o "ProxyCommand=${PROXY_CMD}" "${SSH_USER}@${BACKEND_HOST}" "
    sudo systemctl start k3s 2>/dev/null || true
    echo '--- k3s status ---'
    sudo systemctl is-active k3s 2>/dev/null || echo inactive
    echo '--- port 6443 ---'
    sudo ss -tlnp 2>/dev/null | grep 6443 || echo 'nothing on 6443'
  "
  echo "If k3s is active, start the tunnel and try: export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes"
  exit 0
fi

# Arrêter un tunnel existant
pkill -f "ssh.*${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" 2>/dev/null || true
pkill -f "ssh.*-L ${LOCAL_PORT}:.*6443" 2>/dev/null || true
sleep 1

echo "Starting SSH tunnel 127.0.0.1:${LOCAL_PORT} -> ${BACKEND_HOST}:${REMOTE_PORT} (via ${JUMP_HOST})..."

if [[ "${1:-}" == "--background" ]]; then
  : > /tmp/kubectl-tunnel.log
  setsid ssh -N -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" \
    "${SSH_OPTS[@]}" -o "ProxyCommand=${PROXY_CMD}" "${SSH_USER}@${BACKEND_HOST}" \
    </dev/null >>/tmp/kubectl-tunnel.log 2>&1 &
  # Give SSH a few seconds to establish the tunnel to avoid false negatives.
  for _ in $(seq 1 10); do
    if ss -ltn | grep -q "127.0.0.1:${LOCAL_PORT}"; then
      break
    fi
    sleep 1
  done
  if ! ss -ltn | grep -q "127.0.0.1:${LOCAL_PORT}"; then
    echo "Failed to start tunnel on 127.0.0.1:${LOCAL_PORT}"
    tail -n 40 /tmp/kubectl-tunnel.log || true
    exit 1
  fi
  echo "Tunnel running in background. Wait ~5s then: export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes"
  exit 0
fi

# Foreground
exec ssh -N -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" \
  "${SSH_OPTS[@]}" -o "ProxyCommand=${PROXY_CMD}" "${SSH_USER}@${BACKEND_HOST}"

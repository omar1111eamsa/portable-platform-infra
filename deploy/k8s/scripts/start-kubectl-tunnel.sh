#!/bin/bash
# Démarrer le tunnel vers le cluster k3s via gcloud IAP (backend-vm n'a pas d'IP externe).
# Usage: ./start-kubectl-tunnel.sh [--background] [--ensure-firewall] [--check-vm]
# Prérequis: gcloud configuré, KUBECONFIG=~/.kube/myapp-k3s.yaml (127.0.0.1:16443)
#
# Une fois le tunnel actif: export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes
# Si TLS handshake timeout: sur backend-vm, k3s doit être démarré et écouter sur 0.0.0.0:6443
#   (Ansible k3s-server utilise --bind-address 0.0.0.0). Règle firewall allow-iap-6443 requise.

set -e
LOCAL_PORT=16443
REMOTE_PORT=6443
VM="${VM:-backend-vm}"
PROJECT="${GCP_PROJECT:-quick-keel-483320-b9}"
ZONE="${GCP_ZONE:-europe-west1-b}"

# Option: créer la règle firewall IAP pour le port 6443 (une fois par projet)
if [[ "${1:-}" == "--ensure-firewall" ]]; then
  shift
  if ! gcloud compute firewall-rules describe allow-iap-6443 --project="${PROJECT}" &>/dev/null; then
    echo "Creating firewall rule allow-iap-6443 (IAP -> tcp:6443)..."
    gcloud compute firewall-rules create allow-iap-6443 \
      --project="${PROJECT}" --direction=INGRESS --action=allow \
      --rules=tcp:6443 --source-ranges=35.235.240.0/20 \
      --description="Allow IAP TCP forwarding to k3s API (6443)"
  else
    echo "Firewall rule allow-iap-6443 already exists."
  fi
fi

# Option: via gcloud CLI, vérifier/démarrer k3s sur backend-vm (IAP SSH)
if [[ "${1:-}" == "--check-vm" ]]; then
  shift
  echo "Running on ${VM} via gcloud compute ssh (IAP)..."
  gcloud compute ssh "${VM}" --project="${PROJECT}" --zone="${ZONE}" --command="
    echo '--- k3s service ---'
    sudo systemctl start k3s 2>/dev/null || true
    sudo systemctl is-active k3s 2>/dev/null || echo inactive
    echo '--- port 6443 ---'
    sudo ss -tlnp | grep 6443 || echo 'nothing listening on 6443'
  "
  echo "If k3s is active and 6443 is listening, start the tunnel and try kubectl."
  exit 0
fi

# Arrêter un tunnel existant
pkill -f "start-iap-tunnel ${VM} ${REMOTE_PORT}" 2>/dev/null || true
pkill -f "gcloud compute ssh ${VM}.*${LOCAL_PORT}" 2>/dev/null || true
pkill -f "ssh.*${LOCAL_PORT}:.*${REMOTE_PORT}" 2>/dev/null || true
sleep 1

echo "Starting IAP tunnel 127.0.0.1:${LOCAL_PORT} -> ${VM}:${REMOTE_PORT} ..."
# Disable connection check so tunnel stays up (k3s API uses TLS, check would fail)
IAP_EXTRA=(--iap-tunnel-disable-connection-check)

if [[ "${1:-}" == "--background" ]]; then
  nohup gcloud compute start-iap-tunnel "${VM}" "${REMOTE_PORT}" \
    --local-host-port="127.0.0.1:${LOCAL_PORT}" \
    --project="${PROJECT}" \
    --zone="${ZONE}" \
    "${IAP_EXTRA[@]}" \
    </dev/null >>/tmp/kubectl-tunnel.log 2>&1 &
  echo "Tunnel starting in background (log: /tmp/kubectl-tunnel.log). Wait ~15s then: export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes"
  exit 0
fi

# Foreground
exec gcloud compute start-iap-tunnel "${VM}" "${REMOTE_PORT}" \
  --local-host-port="127.0.0.1:${LOCAL_PORT}" \
  --project="${PROJECT}" \
  --zone="${ZONE}" \
  "${IAP_EXTRA[@]}"

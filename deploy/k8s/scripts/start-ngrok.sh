#!/bin/bash
# Démarre ngrok sur frontend-vm et affiche le domaine.
# Usage: NGROK_AUTHTOKEN=xxx ./start-ngrok.sh
# Ou via gcloud: gcloud compute ssh frontend-vm ... (voir SETUP.md)
set -e

if [[ -z "$NGROK_AUTHTOKEN" ]]; then
  echo "Erreur: NGROK_AUTHTOKEN requis."
  echo "  export NGROK_AUTHTOKEN=ton_token_ngrok"
  echo "  ./start-ngrok.sh"
  exit 1
fi

GCP_PROJECT="${GCP_PROJECT:-quick-keel-483320-b9}"
GCP_ZONE="${GCP_ZONE:-europe-west1-b}"

echo "Configuring ngrok and starting tunnel on frontend-vm..."
gcloud compute ssh frontend-vm --project="$GCP_PROJECT" --zone="$GCP_ZONE" --command="
  mkdir -p /tmp/ngrok-config
  echo 'version: \"2\"' > /tmp/ngrok-config/ngrok.yml
  echo \"authtoken: $NGROK_AUTHTOKEN\" >> /tmp/ngrok-config/ngrok.yml
  pkill ngrok 2>/dev/null || true
  sleep 2
  nohup ngrok http 80 --config /tmp/ngrok-config/ngrok.yml --log=stdout > /tmp/ngrok.log 2>&1 &
  sleep 6
  curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -oE '\"public_url\":\"https?://[^\"]+\"' | head -1
" 2>&1

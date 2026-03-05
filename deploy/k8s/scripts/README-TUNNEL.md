# Tunnel kubectl vers le cluster k3s (backend-vm sans IP externe)

Le serveur k3s est sur **backend-vm**, qui n’a pas d’IP externe. Tout se fait au **gcloud CLI** (IAP pour le tunnel et pour SSH).

## Prérequis

- `gcloud` configuré (projet, zone)
- Kubeconfig : `~/.kube/myapp-k3s.yaml` avec `server: https://127.0.0.1:16443`

## Tout en gcloud CLI

```bash
# 1) Une fois : firewall IAP pour le port 6443
./start-kubectl-tunnel.sh --ensure-firewall
# ou à la main :
gcloud compute firewall-rules create allow-iap-6443 \
  --project=quick-keel-483320-b9 --direction=INGRESS --action=allow \
  --rules=tcp:6443 --source-ranges=35.235.240.0/20

# 2) Si TLS timeout : vérifier/démarrer k3s sur backend-vm (SSH via IAP)
./start-kubectl-tunnel.sh --check-vm
# ou à la main :
gcloud compute ssh backend-vm --project=quick-keel-483320-b9 --zone=europe-west1-b \
  --command="sudo systemctl start k3s; sudo systemctl is-active k3s; sudo ss -tlnp | grep 6443"

# 3) Tunnel puis kubectl
./start-kubectl-tunnel.sh --ensure-firewall --background
sleep 15
export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes
```

## Une fois : règle firewall IAP

Pour que le tunnel IAP puisse atteindre le port 6443 de la VM :

```bash
./start-kubectl-tunnel.sh --ensure-firewall
```

Ou à la main (gcloud uniquement) :

```bash
gcloud compute firewall-rules create allow-iap-6443 \
  --project=quick-keel-483320-b9 \
  --direction=INGRESS --action=allow \
  --rules=tcp:6443 --source-ranges=35.235.240.0/20
```

## Démarrer le tunnel

```bash
# En arrière-plan (recommandé)
./start-kubectl-tunnel.sh --background

# Attendre ~15 s puis tester
export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes
```

Sans `--background`, le tunnel reste en premier plan (terminal bloqué).

## Dépannage

- **Connection refused (127.0.0.1:16443)**  
  Le tunnel n’est pas encore prêt ou s’est arrêté. Relancer `./start-kubectl-tunnel.sh --background` et attendre ~15 s.

- **TLS handshake timeout**  
  Le trafic atteint la VM mais k3s ne répond pas. Via **gcloud CLI** (SSH IAP sur backend-vm) :
  ```bash
  ./start-kubectl-tunnel.sh --check-vm
  ```
  ou : `gcloud compute ssh backend-vm --project=... --zone=... --command="sudo systemctl start k3s; sudo ss -tlnp | grep 6443"`.  
  Sur la VM, k3s doit écouter sur 0.0.0.0:6443 (Ansible `k3s-server` utilise `--bind-address 0.0.0.0`). Si k3s a été installé avant, éditer le service pour ajouter `--bind-address 0.0.0.0`, puis `sudo systemctl daemon-reload && sudo systemctl restart k3s`.

- **Règle firewall**  
  Vérifier que `allow-iap-6443` existe :  
  `gcloud compute firewall-rules describe allow-iap-6443 --project=quick-keel-483320-b9`

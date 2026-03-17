# Kubernetes Manifests — MyApp

Manifests Kubernetes pour déploiement GitOps (ArgoCD).  
Compatible avec réinitialisation des VMs : ordre correct, PVC postgres, Ingress IP, CronJobs disque.

## Structure

```
k8s/
├── base/              # Namespace myapp
├── infra/             # PostgreSQL, Redis, Consul, RabbitMQ
│   ├── postgres/      # PVC, Deployment, Service, init job
│   ├── redis/         # Deployment, Service
│   ├── consul/        # Deployment, Service
│   ├── rabbitmq/      # Deployment, Service
│   └── kustomization.yaml
├── apps/              # API Gateway, Frontend, User, Payment, CRM, etc.
│   ├── api-gateway/
│   ├── execution-engine/ # Realtime execution-engine (RabbitMQ consumer Deployment)
│   ├── frontend/
│   ├── ingress-ip.yaml  # Routage host-based (dev.example.com)
│   └── kustomization.yaml
├── network-policies/  # Default deny + allow-list réseau myapp
├── cronjobs/          # Nettoyage disque (backend-vm, frontend-vm)
├── scripts/           # clean-node-disk.sh (manuel)
└── DEPLOYMENT.md      # Prérequis et ordre de déploiement
```

## Déploiement

### Ordre recommandé

```bash
# 1. Base (namespace)
kubectl apply -k base/

# 2. Infra (PostgreSQL + init-databases Job, Redis, Consul, RabbitMQ)
kubectl apply -k infra/

# 3. Apps (api-gateway, frontend)
kubectl apply -k apps/
```

### Depuis le backend via SSH

```bash
ssh -A -i ~/.ssh/myapp_vms -J hodeconlimited@203.0.113.11 hodeconlimited@10.0.0.11 \
  "sudo k3s kubectl apply -k -" < <(kubectl kustomize deploy/k8s/base)
```

Ou en une fois :
```bash
kubectl apply -k deploy/k8s/
```

Voir [DEPLOYMENT.md](DEPLOYMENT.md) pour les prérequis (ghcr-secret, noms de nœuds).
Voir [CHECKLIST.md](CHECKLIST.md) pour la liste des configurations manquantes (DevOps + développeurs).

### Préflight (avant release)

```bash
export KUBECONFIG=~/.kube/myapp-k3s.yaml
./deploy/k8s/scripts/preflight-check.sh
```

### ArgoCD

Configurer une Application ArgoCD pointant vers ce dépôt, path `deploy/k8s/`.

## Images

| Service     | Image                                      |
|-------------|---------------------------------------------|
| api-gateway | ghcr.io/myapp/backend-api-gateway    |
| frontend    | ghcr.io/myapp/front-end              |
| execution-engine | ghcr.io/myapp/cq-execution-engine |

## Ingress (k3s + Traefik)

- **dev.example.com** → api-gateway:8888 (API, login, oauth2, chatbot, payment-service)
- **dev.example.com** → frontend:3000 (app) and same API paths
- **dashboard.example.com** → admin-frontend:8080
- **dev.example.com/argocd** → ArgoCD UI
- Local: `api.localhost`, `app.localhost`.

## Dépannage : Pression disque (Evicted, DiskPressure)

Si des pods sont **Evicted** (motif `ephemeral-storage` / `DiskPressure`), libérer l’espace sur le nœud concerné. **Sur chaque VM** (backend-vm, frontend-vm, backend2) :

```bash
# Nettoyage des images inutilisées (sans supprimer les pods en cours)
sudo crictl rmi --prune
```

Ne pas utiliser `crictl rmp -a` (tente de supprimer tous les pods). Optionnel : script `deploy/k8s/scripts/clean-node-disk.sh` si présent. Puis supprimer les pods évincés :

```bash
kubectl delete pods -n myapp --field-selector=status.phase=Failed
```

Voir aussi `apps/metamodel-orchestration/README.md` pour le metamodel (API + scheduler + dag-processor + worker + triggerer, mode CeleryExecutor, diagnostics de santé).
Voir aussi `apps/execution-engine/README.md` pour le mode realtime execution-engine.

## Sécurité

- **Secret postgres** : remplacer les credentials en prod (Sealed Secrets, Vault)
- **Images** : préférer des tags fixes (ex: `v1.0.0`) plutôt que `latest`

## Ajouter un service

1. Créer `apps/<nom-service>/deployment.yaml`, `service.yaml`
2. Ajouter les resources dans `apps/kustomization.yaml`
3. Respecter les conventions (voir [ARCHITECTURE-K8S.md](../docs/ARCHITECTURE-K8S.md))

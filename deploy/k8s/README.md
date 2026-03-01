# Kubernetes Manifests — MyApp

Manifests Kubernetes pour déploiement GitOps (ArgoCD).  
Compatible avec réinitialisation des VMs : ordre correct, PVC postgres, Ingress IP, CronJobs disque.

## Structure

```
k8s/
├── base/              # Namespace myapp
├── infra/             # PostgreSQL, Redis, Consul, RabbitMQ
│   ├── postgres/      # Secret, PVC, Deployment, Service
│   ├── redis/         # Deployment, Service
│   ├── consul/        # Deployment, Service
│   ├── rabbitmq/      # Deployment, Service
│   └── kustomization.yaml
├── apps/              # API Gateway, Frontend, User, Payment, CRM, etc.
│   ├── api-gateway/
│   ├── frontend/
│   ├── ingress-ip.yaml  # Accès par IP (http://203.0.113.10)
│   └── kustomization.yaml
├── cronjobs/          # Nettoyage disque (backend-vm, frontend-vm)
├── scripts/           # clean-node-disk.sh (manuel)
└── DEPLOYMENT.md      # Prérequis et ordre de déploiement
```

## Déploiement

### Ordre recommandé

```bash
# 1. Base (namespace)
kubectl apply -k base/

# 2. Infra (PostgreSQL, Redis, Consul)
kubectl apply -k infra/

# 3. Apps (api-gateway, frontend)
kubectl apply -k apps/
```

### Depuis le backend via SSH

```bash
ssh -A -i ~/.ssh/myapp_vms -J hodeconlimited@203.0.113.10 hodeconlimited@10.0.0.11 \
  "sudo k3s kubectl apply -k -" < <(kubectl kustomize deploy/k8s/base)
```

Ou en une fois :
```bash
kubectl apply -k deploy/k8s/
```

Voir [DEPLOYMENT.md](DEPLOYMENT.md) pour les prérequis (ghcr-secret, noms de nœuds).
Voir [CHECKLIST.md](CHECKLIST.md) pour la liste des configurations manquantes (DevOps + développeurs).

### ArgoCD

Configurer une Application ArgoCD pointant vers ce dépôt, path `deploy/k8s/`.

## Images

| Service     | Image                                      |
|-------------|---------------------------------------------|
| api-gateway | ghcr.io/myapp/backend-api-gateway    |
| frontend    | ghcr.io/myapp/front-end              |

## Ingress (k3s + Traefik)

- API : `api.localhost` → api-gateway:8888
- App : `app.localhost` → frontend:3000

Adapter les hosts dans les fichiers Ingress selon ton domaine.

## Dépannage : Pression disque (ImagePullBackOff, Evicted)

Si des pods sont `Evicted` avec le motif `ephemeral-storage`, libérer de l'espace sur chaque nœud :

```bash
# Depuis ta machine (remplacer user et IP par tes identifiants)
for node in 10.0.0.11 10.0.0.12; do
  ssh -A -i ~/.ssh/myapp_vms -J hodeconlimited@203.0.113.10 hodeconlimited@$node \
    'sudo bash -s' < deploy/k8s/scripts/clean-node-disk.sh
done
```

Ou manuellement sur chaque VM :

```bash
sudo bash deploy/k8s/scripts/clean-node-disk.sh
```

Puis supprimer les pods éjectés et laisser les ReplicaSets recréer :

```bash
kubectl delete pods -n myapp --field-selector=status.phase=Failed
```

## Sécurité

- **Secret postgres** : remplacer les credentials en prod (Sealed Secrets, Vault)
- **Images** : préférer des tags fixes (ex: `v1.0.0`) plutôt que `latest`

## Ajouter un service

1. Créer `apps/<nom-service>/deployment.yaml`, `service.yaml`
2. Ajouter les resources dans `apps/kustomization.yaml`
3. Respecter les conventions (voir ARCHITECTURE.md)

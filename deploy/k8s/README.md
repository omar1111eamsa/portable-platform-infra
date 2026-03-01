# Kubernetes Manifests — MyApp

Manifests Kubernetes pour déploiement GitOps (ArgoCD).

## Structure

```
k8s/
├── base/              # Namespace myapp
│   ├── namespace.yaml
│   └── kustomization.yaml
├── infra/             # PostgreSQL, Redis, Consul
│   ├── postgres/      # Secret, PVC, Deployment, Service
│   ├── redis/         # Deployment, Service
│   ├── consul/        # Deployment, Service
│   └── kustomization.yaml
└── apps/              # Applications
    ├── api-gateway/   # Deployment, Service, Ingress
    ├── frontend/      # Deployment, Service, Ingress
    └── kustomization.yaml
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

Ou copier les manifests et appliquer :

```bash
kubectl apply -k deploy/k8s/base/
kubectl apply -k deploy/k8s/infra/
kubectl apply -k deploy/k8s/apps/
```

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

## Sécurité

- **Secret postgres** : remplacer les credentials en prod (Sealed Secrets, Vault)
- **Images** : préférer des tags fixes (ex: `v1.0.0`) plutôt que `latest`

## Ajouter un service

1. Créer `apps/<nom-service>/deployment.yaml`, `service.yaml`
2. Ajouter les resources dans `apps/kustomization.yaml`
3. Respecter les conventions (voir ARCHITECTURE.md)

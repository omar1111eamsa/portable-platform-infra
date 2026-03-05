# Architecture du cluster MyApp — Kubernetes

Ce document décrit l’architecture globale du cluster et le rôle de chaque fichier de configuration K8s.

---

## 1. Vue d’ensemble

- **Cluster** : k3s (2 nœuds : backend-vm, frontend-vm)
- **Namespace principal** : `myapp`
- **Ingress** : Traefik (intégré k3s)
- **GitOps** : ArgoCD observe la branche `test-argocd`, path `deploy/k8s`
- **Accès externe** : `https://example.ngrok-free.app`

### Flux réseau (simplifié)

```
Internet (ngrok) → Traefik Ingress
  ├── /api, /login, /oauth2  → api-gateway:8888
  ├── /chatbot               → IngressRoute → stripPrefix → chatbot:8000
  ├── /argocd                → argocd-server:80 (namespace argocd)
  └── /                      → frontend:3000

api-gateway → Consul (service discovery) → user-service, crmservice, payment-service,
             prediction-intake-service, kpi-service
```

---

## 2. Structure Kustomize (ordre d’application)

```
deploy/k8s/
├── kustomization.yaml     # Racine : base → infra → apps → cronjobs → argocd
├── base/                  # Namespace
├── infra/                 # PostgreSQL, Redis, Consul, RabbitMQ
├── apps/                  # API Gateway, Frontend, tous les backends
├── cronjobs/              # Nettoyage disque et pods evicted
└── argocd/                # Ingress pour l’UI ArgoCD
```

---

## 3. Détail des fichiers par section

### 3.1 Base (`base/`)

| Fichier | Rôle |
|---------|------|
| **kustomization.yaml** | Référence `namespace.yaml`. |
| **namespace.yaml** | Crée le namespace `myapp` avec labels (managed-by: argocd). |

---

### 3.2 Infra (`infra/`)

Namespace : `myapp`. Tous les services sont en ClusterIP.

#### PostgreSQL

| Fichier | Rôle |
|---------|------|
| **postgres/secret.yaml** | Secret `postgres-credentials` (user, password, etc.). |
| **postgres/pvc.yaml** | PVC 5Gi (ReadWriteOnce, StorageClass par défaut, ex. local-path). |
| **postgres/deployment.yaml** | 1 replica, image postgres:16-alpine, volume monté sur `/var/lib/postgresql/data`. |
| **postgres/service.yaml** | Service ClusterIP port 5432. |

#### Redis

| Fichier | Rôle |
|---------|------|
| **redis/deployment.yaml** | 2 replicas, image Redis. |
| **redis/service.yaml** | ClusterIP 6379. |

#### Consul

| Fichier | Rôle |
|---------|------|
| **consul/deployment.yaml** | 1 replica, bootstrap-expect=1 (pas de HA). Découverte de services pour l’API Gateway. |
| **consul/service.yaml** | ClusterIP 8500 (HTTP), 8600 (DNS). |

#### RabbitMQ

| Fichier | Rôle |
|---------|------|
| **rabbitmq/deployment.yaml** | 2 replicas, message broker. |
| **rabbitmq/service.yaml** | ClusterIP 5672 (AMQP), 15672 (management UI). |

---

### 3.3 Apps (`apps/`)

Namespace : `myapp`. Chaque service a typiquement : Deployment, Service, Ingress (host `*.localhost`). Le chatbot a en plus : Middleware, IngressRoute, PVC.

#### API Gateway

| Fichier | Rôle |
|---------|------|
| **api-gateway/deployment.yaml** | 2 replicas, image GHCR, port 8888, env (JWT, CORS, etc.), probes HTTP /health. |
| **api-gateway/service.yaml** | ClusterIP 8888. |
| **api-gateway/ingress.yaml** | Ingress Traefik pour `api.localhost` → api-gateway:8888. |

#### Frontend

| Fichier | Rôle |
|---------|------|
| **frontend/deployment.yaml** | 2 replicas, image front-end, port 3000. |
| **frontend/service.yaml** | ClusterIP 3000. |
| **frontend/ingress.yaml** | Ingress pour `app.localhost` → frontend:3000. |

#### Chatbot

| Fichier | Rôle |
|---------|------|
| **chatbot/middleware.yaml** | Middleware Traefik **StripPrefix** : enlève `/chatbot` avant d’envoyer au backend. |
| **chatbot/ingressroute.yaml** | IngressRoute (CRD Traefik) : host ngrok + PathPrefix `/chatbot` → service chatbot:8000 + middleware strip. |
| **chatbot/pvc.yaml** | PVC 1Gi pour la base SQLite (`/data/chatbot.db`). |
| **chatbot/deployment.yaml** | 1 replica, image GHCR, env LLM_API_KEY (secret), DB_PATH=/data/chatbot.db, volumeMount sur `/data`, fsGroup 1000. |
| **chatbot/service.yaml** | ClusterIP 8000. |
| **chatbot/ingress.yaml** | Ingress pour `chatbot.localhost` → chatbot:8000 (usage local). |

#### CRM Client

| Fichier | Rôle |
|---------|------|
| **crm-client/deployment.yaml** | 2 replicas, image backend-crm-client, enregistrement Consul `crmservice`. |
| **crm-client/service.yaml** | ClusterIP 8083. |
| **crm-client/ingress.yaml** | Ingress `crm.localhost` → crm-client. |

#### KPI Dashboard

| Fichier | Rôle |
|---------|------|
| **kpi-dashboard/deployment.yaml** | 1 replica, image backend-kpi-dashboard-notifications, Consul `kpi-service`. |
| **kpi-dashboard/service.yaml** | ClusterIP 8084. |
| **kpi-dashboard/ingress.yaml** | Ingress `kpi.localhost`. |

#### Payment Service

| Fichier | Rôle |
|---------|------|
| **payment-service/deployment.yaml** | 2 replicas, Stripe, RabbitMQ, etc. |
| **payment-service/service.yaml** | ClusterIP 8082/8083. |
| **payment-service/ingress.yaml** | Ingress `payment.localhost`. |

#### Predictions Intake

| Fichier | Rôle |
|---------|------|
| **predictions-intake/deployment.yaml** | 2 replicas, Consul `prediction-intake-service`. |
| **predictions-intake/service.yaml** | ClusterIP 8082. |
| **predictions-intake/ingress.yaml** | Ingress `predictions.localhost`. |

#### User Management

| Fichier | Rôle |
|---------|------|
| **user-management/deployment.yaml** | 2 replicas, Consul `user-service`, env depuis secret. |
| **user-management/service.yaml** | ClusterIP 8081 (service principal). |
| **user-management/user-service.yaml** | Service additionnel (alias / même sélecteur si besoin). |
| **user-management/ingress.yaml** | Ingress `users.localhost`. |
| **user-management/secret.yaml** | Secret pour JWT, OAuth Google, etc. (référencé par le deployment). |

#### Ingress IP / ngrok (partagé)

| Fichier | Rôle |
|---------|------|
| **ingress-ip.yaml** | Deux Ingress pour accès par IP et domaine ngrok : **ingress-ip-api** (priorité 200) : `/api`, `/login`, `/oauth2` → api-gateway. **ingress-ip-frontend** (priorité 100) : `/` → frontend. Host : `example.ngrok-free.app` + règle sans host (IP). |

Le chemin `/chatbot` est géré par l’IngressRoute Traefik (chatbot), pas par ce fichier.

---

### 3.4 CronJobs (`cronjobs/`)

Namespace : `myapp`. Maintenance disque et nettoyage des pods.

| Fichier | Rôle |
|---------|------|
| **clean-disk-backend.yaml** | CronJob `*/30 * * * *` : exécute un script de nettoyage disque sur le nœud **backend-vm** (nodeName ou nodeSelector). |
| **clean-disk-frontend.yaml** | CronJob `15,45 * * * *` : même chose pour **frontend-vm**. |
| **clean-evicted-pods-rbac.yaml** | ServiceAccount + Role + RoleBinding pour le CronJob qui supprime les pods. |
| **clean-evicted-pods.yaml** | CronJob `*/30 * * * *` : utilise l’image `bitnami/kubectl`, supprime les pods en `Failed` et `Succeeded` dans `myapp` (évite l’accumulation de pods evicted). |

---

### 3.5 ArgoCD (`argocd/`)

Namespace : **argocd** (ArgoCD est installé à part, ces manifests n’installent pas ArgoCD, ils exposent son UI).

| Fichier | Rôle |
|---------|------|
| **argocd/kustomization.yaml** | Référence `ingress.yaml`, namespace `argocd`. |
| **argocd/ingress.yaml** | Ingress Traefik : path `/argocd` (host ngrok ou sans host) → service `argocd-server:80` dans le namespace `argocd`. Permet d’accéder à l’UI ArgoCD via le même domaine. |

Prérequis côté ArgoCD : `server.insecure`, `server.basehref=/argocd`, `server.rootpath=/argocd` (ConfigMap argocd-cmd-params-cm).

---

## 4. Récapitulatif des types de ressources

| Type | Utilisation |
|------|-------------|
| **Namespace** | `myapp` (base), `argocd` (argocd). |
| **Secret** | postgres, user-management, chatbot-credentials (créés manuellement ou via secret.yaml). |
| **PersistentVolumeClaim** | postgres (5Gi), chatbot (1Gi). |
| **Deployment** | Tous les services applicatifs + infra (postgres, redis, consul, rabbitmq). |
| **Service** | ClusterIP pour chaque deployment. |
| **Ingress** | Traefik, par host (*.localhost) + ingress-ip (ngrok / IP). |
| **IngressRoute** | Traefik CRD : chatbot avec stripPrefix. |
| **Middleware** | Traefik CRD : stripPrefix pour /chatbot. |
| **CronJob** | Nettoyage disque (backend/frontend), suppression pods evicted. |
| **ServiceAccount / Role / RoleBinding** | Pour le CronJob clean-evicted-pods. |

---

## 5. Secrets non versionnés (à créer à la main)

- **ghcr-secret** : `docker-registry` pour tirer les images GHCR.
- **chatbot-credentials** : clé `LLM_API_KEY` (OpenRouter).
- **stripe-credentials**, **google-oauth-credentials**, **mail-credentials** : selon les services.

Voir `deploy/k8s/CHECKLIST.md` et `deploy/k8s/apps/chatbot/SECRET-SETUP.md` pour les commandes.

---

## 6. Ordre d’application (Kustomize)

1. **base** : namespace `myapp`.
2. **infra** : postgres (secret, PVC, deployment, service), redis, consul, rabbitmq.
3. **apps** : gateway, frontend, chatbot (middleware, ingressroute, pvc, deployment, service, ingress), puis les autres services, puis **ingress-ip.yaml**.
4. **cronjobs** : CronJobs + RBAC.
5. **argocd** : Ingress ArgoCD (namespace argocd).

ArgoCD applique tout via `kubectl apply -k deploy/k8s` (ou équivalent) depuis le dépôt portable-platform-infra, branche `test-argocd`.

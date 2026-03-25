# Architecture du cluster MyApp — Kubernetes

Ce document décrit l’architecture globale du cluster et le rôle de chaque fichier de configuration K8s.

---

## 1. Vue d’ensemble

- **Cluster** : k3s (3 nœuds : backend-vm, frontend-vm, backend2)
- **Namespace principal** : `myapp`
- **Ingress** : Traefik (intégré k3s)
- **GitOps** : ArgoCD observe la branche `test-argocd`, path `deploy/k8s`
- **Accès externe** :
  - `https://dev.example.com` (frontend + API)
  - `https://dashboard.example.com` (admin-frontend)
  - `http://airflow.dev.example.com` (exposition Airflow temporaire pour dev)
  - `https://dev.example.com/pgadmin` (pgAdmin derrière Traefik, usage dev)

### Flux réseau (simplifié)

```
Internet → Traefik Ingress
  ├── /api, /login, /oauth2, /chatbot, /payment-service  → api-gateway:8888 (JWT requis pour /chatbot)
  ├── /argocd                          → argocd-server:80 (namespace argocd)
  ├── host dev.example.com, /          → frontend:3000
  └── host dashboard.example.com, /    → admin-frontend:8080

api-gateway → user-service (validate-token), chatbot:8000 (/chatbot), Consul → crmservice,
             payment-service, prediction-intake-service, kpi-service
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
| **postgres/pvc.yaml** | PVC 5Gi (ReadWriteOnce, local-path). |
| **postgres/deployment.yaml** | 1 replica, nodeSelector backend-vm, image postgres:16-alpine, volume sur `/var/lib/postgresql/data`. |
| **postgres/service.yaml** | Service ClusterIP port 5432. |

#### Redis

| Fichier | Rôle |
|---------|------|
| **redis/deployment.yaml** | 1 replica, nodeSelector **frontend-vm**, image Redis. |
| **redis/service.yaml** | ClusterIP 6379. |

#### Consul

| Fichier | Rôle |
|---------|------|
| **consul/deployment.yaml** | 1 replica, nodeSelector backend-vm, bootstrap-expect=1. Découverte de services pour l’API Gateway. |
| **consul/service.yaml** | ClusterIP 8500 (HTTP), 8600 (DNS). |

#### RabbitMQ

| Fichier | Rôle |
|---------|------|
| **rabbitmq/deployment.yaml** | 1 replica, nodeSelector backend-vm, message broker. |
| **rabbitmq/service.yaml** | ClusterIP 5672 (AMQP), 15672 (management UI). |

---

### 3.3 Apps (`apps/`)

Namespace : `myapp`. En production, le routage externe passe par `apps/ingress-ip.yaml` (host `dev.example.com`). Les ingress `*.localhost` sont réservés au local.

#### API Gateway

| Fichier | Rôle |
|---------|------|
| **api-gateway/deployment.yaml** | 1 replica, nodeSelector frontend-vm, image GHCR, port 8888, env (JWT, CORS, etc.), probes HTTP /health. Lit `JWT_SECRET` depuis le secret partagé `auth-credentials`. |
| **api-gateway/service.yaml** | ClusterIP 8888. |
| **api-gateway/ingress.yaml** | Ingress Traefik pour `api.localhost` → api-gateway:8888. |

#### Frontend

| Fichier | Rôle |
|---------|------|
| **frontend/deployment.yaml** | 1 replica, nodeSelector frontend-vm, image front-end, port 3000. |
| **frontend/service.yaml** | ClusterIP 3000. |
| **frontend/ingress.yaml** | Ingress pour `app.localhost` → frontend:3000. |

#### Admin Frontend

| Fichier | Rôle |
|---------|------|
| **admin-frontend/deployment.yaml** | 1 replica, nodeSelector frontend-vm, image admin front-end, port 8080. |
| **admin-frontend/service.yaml** | ClusterIP 8080. |

#### Chatbot

| Fichier | Rôle |
|---------|------|
| **chatbot/ingressroute.yaml** | Optionnel (CRD Traefik IngressRoute). Sinon `/chatbot` est servi par **ingress-ip-api**. |
| **chatbot/pvc.yaml** | PVC 1Gi pour SQLite (`/data/chatbot.db`). **Node affinity** : PVC local-path sur frontend-vm. |
| **chatbot/deployment.yaml** | 1 replica, nodeSelector **frontend-vm**, image GHCR, env LLM_API_KEY (secret), DB_PATH=/data/chatbot.db, volumeMount sur `/data`. |
| **chatbot/service.yaml** | ClusterIP 8000. |
| **chatbot/ingress.yaml** | Ingress pour `chatbot.localhost` → chatbot:8000 (usage local). |

#### CRM Client

| Fichier | Rôle |
|---------|------|
| **crm-client/deployment.yaml** | 1 replica, nodeSelector frontend-vm, image backend-crm-client, Consul `crmservice`. |
| **crm-client/service.yaml** | ClusterIP 8083. |
| **crm-client/ingress.yaml** | Ingress `crm.localhost` → crm-client. |

#### KPI Dashboard

| Fichier | Rôle |
|---------|------|
| **kpi-dashboard/deployment.yaml** | 1 replica, nodeSelector frontend-vm, image backend-kpi-dashboard-notifications, Consul `kpi-service`. |
| **kpi-dashboard/service.yaml** | ClusterIP 8084. |
| **kpi-dashboard/ingress.yaml** | Ingress `kpi.localhost`. |

#### Payment Service

| Fichier | Rôle |
|---------|------|
| **payment-service/deployment.yaml** | 1 replica, nodeSelector frontend-vm, Stripe, RabbitMQ. |
| **payment-service/service.yaml** | ClusterIP 8082/8083. |
| **payment-service/ingress.yaml** | Ingress `payment.localhost`. |

#### Predictions Intake

| Fichier | Rôle |
|---------|------|
| **predictions-intake/deployment.yaml** | 1 replica, nodeSelector frontend-vm, Consul `prediction-intake-service`, enregistrement forcé sur `status.podIP` (`prefer-ip-address=true`) pour éviter les `UnknownHostException` côté gateway. |
| **predictions-intake/service.yaml** | ClusterIP 8082. |
| **predictions-intake/ingress.yaml** | Ingress `predictions.localhost`. |

#### User Management

| Fichier | Rôle |
|---------|------|
| **user-management/deployment.yaml** | 1 replica, nodeSelector **frontend-vm**, Consul `user-service`, env depuis secret. Lit `JWT_SECRET` depuis le secret partagé `auth-credentials` comme l'API Gateway. |
| **user-management/service.yaml** | ClusterIP 8081. |
| **user-management/user-service.yaml** | Service alias `user-service` (ClusterIP 8081) pointant sur les mêmes pods. |
| **user-management/ingress.yaml** | Ingress `users.localhost`. |
| **user-management/secret.yaml** | Référencé par le deployment (OAuth Google, etc.). |

#### Metamodel-orchestration (Airflow)

| Fichier | Rôle |
|---------|------|
| **metamodel-orchestration/deployment.yaml** | API server Airflow (1 replica), nodeSelector backend2, tolère DiskPressure. Airflow configuré en **CeleryExecutor** (Redis broker). Métadonnées Airflow : PostgreSQL via secret `metamodel-db-credentials`. |
| **metamodel-orchestration/scheduler-deployment.yaml** | Scheduler Airflow (1 replica) sur backend2 (CeleryExecutor + Redis broker). |
| **metamodel-orchestration/dag-processor-deployment.yaml** | DAG processor Airflow 3 (1 replica) sur backend2 (CeleryExecutor + Redis broker). |
| **metamodel-orchestration/worker-deployment.yaml** | Celery worker Airflow (1 replica) sur backend2. Exécute les tâches asynchrones du DAG. |
| **metamodel-orchestration/triggerer-deployment.yaml** | Triggerer Airflow (1 replica) sur backend2 pour les opérateurs/sensors deferrables. |
| **metamodel-orchestration/service.yaml** | ClusterIP 8080 (service interne, non exposé par le gateway). |

#### Execution Engine (Realtime)

| Fichier | Rôle |
|---------|------|
| **execution-engine/configmap.yaml** | Configuration optionnelle du moteur d’exécution. |
| **execution-engine/deployment.yaml** | **Deployment** `execution-engine` sur `backend2`, consumer RabbitMQ realtime (`execution.events` / `trade_signal.created`) qui alimente `filled_trades`. Le consumer accepte maintenant le payload legacy `orders[].orderId` et le format moderne `signal_id`. |
| **execution-engine/secret.yaml.example** | Exemple de secret broker credentials (Binance). |

#### pgAdmin

| Fichier | Rôle |
|---------|------|
| **pgadmin/deployment.yaml** | 1 replica, nodeSelector frontend-vm, interface d'administration PostgreSQL pour usage dev. |
| **pgadmin/service.yaml** | ClusterIP 80. |
| **pgadmin/ingress.yaml** | Exposition via `https://dev.example.com/pgadmin` avec `SCRIPT_NAME=/pgadmin`. |
| **pgadmin/middleware-strip-prefix.yaml** | Middleware Traefik présent dans le repo mais non utilisé sur le chemin final, afin de conserver le préfixe `/pgadmin`. |

#### Ingress (domaines + IP)

| Fichier | Rôle |
|---------|------|
| **ingress-ip.yaml** | **ingress-ip-api** (priorité 200) : host `dev.example.com` → `/api`, `/login`, `/oauth2`, `/chatbot`, `/payment-service` → api-gateway. **ingress-ip-frontend** (priorité 100) : host `dev.example.com` → `/` → frontend. **ingress-dashboard-admin** (priorité 110) : host `dashboard.example.com` → `/` → admin-frontend:8080. |

Le chemin `/chatbot` est défini dans **ingress-ip.yaml** (route vers api-gateway). Optionnel : **chatbot/ingressroute.yaml** si le CRD IngressRoute Traefik est installé.

---

### 3.4 CronJobs (`cronjobs/`)

Namespace : `myapp`. Maintenance disque et nettoyage des pods.

| Fichier | Rôle |
|---------|------|
| **clean-disk-backend.yaml** | CronJob `*/30 * * * *` : exécute un script de nettoyage disque sur le nœud **backend-vm** (nodeName ou nodeSelector). |
| **clean-disk-frontend.yaml** | CronJob `15,45 * * * *` : même chose pour **frontend-vm**. |
| **clean-evicted-pods-rbac.yaml** | ServiceAccount + Role + RoleBinding pour le CronJob qui supprime les pods. |
| **clean-evicted-pods.yaml** | CronJob `*/30 * * * *` : utilise l’image `bitnami/kubectl`, supprime les pods en `Failed` et `Succeeded` dans `myapp` (évite l’accumulation de pods evicted). |
| **metamodel-health-check.yaml** | CronJob `*/5 * * * *` : vérifie l'endpoint `http://metamodel-orchestration.myapp.svc.cluster.local:8080/api/v2/monitor/health` directement via HTTP, sans dépendre du control-plane Kubernetes. |

---

### 3.5 ArgoCD (`argocd/`)

Namespace : **argocd** (ArgoCD est installé à part, ces manifests n’installent pas ArgoCD, ils exposent son UI).

| Fichier | Rôle |
|---------|------|
| **argocd/kustomization.yaml** | Référence `ingress.yaml`, namespace `argocd`. |
| **argocd/ingress.yaml** | Ingress Traefik : path `/argocd` (host dev.example.com ou sans host) → service `argocd-server:80` dans le namespace `argocd`. Permet d’accéder à l’UI ArgoCD via le même domaine. |

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
| **Ingress** | Traefik, ingress principaux `dev.example.com` et `dashboard.example.com` via `ingress-ip.yaml` (+ ingress locaux `*.localhost` pour dev local). |
| **IngressRoute** | Traefik CRD : chatbot → api-gateway. |
| **CronJob** | Nettoyage disque (backend/frontend), suppression pods evicted, health-check metamodel. |
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
3. **apps** : gateway, frontend, chatbot (ingressroute, pvc, deployment, service, ingress), puis les autres services, puis **ingress-ip.yaml**.
4. **cronjobs** : CronJobs + RBAC.
5. **argocd** : Ingress ArgoCD (namespace argocd).

ArgoCD applique tout via `kubectl apply -k deploy/k8s` (ou équivalent) depuis le dépôt portable-platform-infra, branche `test-argocd`.

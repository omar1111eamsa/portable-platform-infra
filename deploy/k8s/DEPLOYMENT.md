# Déploiement — Prérequis et ordre

> **Voir aussi** : [CHECKLIST.md](CHECKLIST.md) pour la liste des configurations manquantes (DevOps + développeurs).

## Prérequis avant `kubectl apply`

### 1. Cluster k3s
- 3 nœuds : `backend-vm` (10.0.0.11), `frontend-vm` (IP publique du jumphost + 10.0.0.12), `backend2` (10.0.0.13)
- Control-plane k3s sur backend-vm, workers sur frontend-vm et backend2. Noms exacts : `backend-vm`, `frontend-vm`, `backend2`
- **Répartition actuelle (nodeSelector)** :
  - **backend-vm** : postgres, consul, rabbitmq (control-plane + infra stateful)
  - **frontend-vm** : api-gateway, frontend, redis, chatbot, user-management, crm-client, kpi-dashboard, payment-service, predictions-intake
  - **backend2** : metamodel-orchestration, metamodel-scheduler, metamodel-dag-processor, metamodel-worker, metamodel-triggerer, execution-engine (Deployment realtime)

### 1b. Accès kubectl depuis ta machine (backend-vm sans IP externe)
- Tunnel SSH : `deploy/k8s/scripts/start-kubectl-tunnel.sh --background`  
  Puis : `export KUBECONFIG=~/.kube/myapp-k3s.yaml && kubectl get nodes`
- Guide complet : [SETUP.md](../SETUP.md)
- Si **TLS handshake timeout** : `./start-kubectl-tunnel.sh --check-vm` (vérifie k3s sur backend via SSH).

### 2. Secrets à créer manuellement

```bash
# Secret GHCR (images privées)
kubectl create secret docker-registry ghcr-secret \
  --namespace=myapp \
  --docker-server=ghcr.io \
  --docker-username=TON_GITHUB_USERNAME \
  --docker-password=TON_GITHUB_PAT

# Postgres (infra)
kubectl create secret generic postgres-credentials -n myapp \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=remplacer-par-un-mot-de-passe-fort \
  --from-literal=POSTGRES_DB=userdb

# RabbitMQ (infra + apps)
kubectl create secret generic rabbitmq-credentials -n myapp \
  --from-literal=RABBITMQ_DEFAULT_USER=remplacer-user \
  --from-literal=RABBITMQ_DEFAULT_PASS=remplacer-password \
  --from-literal=RABBITMQ_DEFAULT_VHOST=/ \
  --from-literal=RABBITMQ_USERNAME=remplacer-user \
  --from-literal=RABBITMQ_PASSWORD=remplacer-password \
  --from-literal=RABBITMQ_VHOST=/ \
  --from-literal=RABBITMQ_ADDRESSES='amqp://remplacer-user:remplacer-password@rabbitmq:5672/'

# Consul UI BasicAuth (Traefik middleware)
CONSUL_HASH="$(openssl passwd -apr1 'change-me-consul-ui')"
kubectl create secret generic consul-ui-basic-auth -n myapp \
  --from-literal=users="admin:${CONSUL_HASH}"

# Stripe (payment-service)
kubectl create secret generic stripe-credentials -n myapp \
  --from-literal=STRIPE_API_KEY=sk_test_xxx \
  --from-literal=STRIPE_WEBHOOK_SECRET=whsec_xxx

# Google OAuth (user-management) — REQUIS pour Sign in with Google
# Use dev.example.com (or your API/frontend host)
kubectl create secret generic google-oauth-credentials -n myapp \
  --from-literal=GOOGLE_CLIENT_ID=ton-client-id.apps.googleusercontent.com \
  --from-literal=GOOGLE_CLIENT_SECRET=ton-client-secret \
  --from-literal=GOOGLE_REDIRECT_URI=https://dev.example.com/login/oauth2/code/google \
  --from-literal=FRONTEND_URL=https://dev.example.com

# Mail SMTP (user-management) — requis pour envoi d'emails
kubectl create secret generic mail-credentials -n myapp \
  --from-literal=SPRING_MAIL_USERNAME=ton-email@example.com \
  --from-literal=SPRING_MAIL_PASSWORD=ton-mot-de-passe-app

# JWT partagé (api-gateway + user-management)
kubectl create secret generic auth-credentials -n myapp \
  --from-literal=JWT_SECRET=remplacer-par-une-cle-hex-forte

# Metamodel DB URLs (Airflow DAG)
kubectl create secret generic metamodel-db-credentials -n myapp \
  --from-literal=MYAPP_DB_URL='postgresql://<POSTGRES_USER>:<POSTGRES_PASSWORD>@postgres:5432/prediction_db' \
  --from-literal=AIRFLOW_CONN_POSTGRES_MYAPP='postgresql://<POSTGRES_USER>:<POSTGRES_PASSWORD>@postgres:5432/prediction_db'

# Optional: broker credentials for execution-engine
kubectl create secret generic execution-engine-broker-credentials -n myapp \
  --from-literal=BINANCE_API_KEY=... \
  --from-literal=BINANCE_SECRET_KEY=...

# Pour mettre à jour le secret existant :
# kubectl create secret generic google-oauth-credentials -n myapp \
#   --from-literal=GOOGLE_CLIENT_ID=... \
#   --from-literal=GOOGLE_CLIENT_SECRET=... \
#   --from-literal=GOOGLE_REDIRECT_URI=https://dev.example.com/login/oauth2/code/google \
#   --from-literal=FRONTEND_URL=https://dev.example.com \
#   --dry-run=client -o yaml | kubectl apply -f -
```

### 3. Namespace
Créé automatiquement par `base/`.

---

## Ordre de déploiement

```bash
# 1. Base (namespace)
kubectl apply -k deploy/k8s/base/

# 2. Créer ghcr-secret (voir ci-dessus)
# 3. Infra (postgres, redis, consul, rabbitmq) + init-databases Job (crée payment_db, crm_db, prediction_db, kpi_db ; pas de base airflow)
kubectl apply -k deploy/k8s/infra/

# 4. Attendre que postgres, redis, consul, rabbitmq soient Ready
kubectl get pods -n myapp -w

# 5. Apps
kubectl apply -k deploy/k8s/apps/

# 6. CronJobs (nettoyage disque)
kubectl apply -k deploy/k8s/cronjobs/
```

Ou en une fois :
```bash
kubectl apply -k deploy/k8s/
```

---

## Après réinitialisation des VMs

1. Réinstaller k3s sur les 3 nœuds (backend-vm, frontend-vm, backend2)
2. Recréer le namespace et les secrets (ghcr-secret, postgres si besoin)
3. `kubectl apply -k deploy/k8s/`
4. Les PVC (postgres) survivent si le storage class conserve les volumes

---

## Vérification

```bash
kubectl get pods -n myapp
kubectl get ingress -n myapp
curl -k -s https://dev.example.com/
curl -k -s https://dev.example.com/api/actuator/health
curl -k -I https://airflow.dev.example.com/
```

### Vérifier OAuth2 Google (Sign in with Google)

```bash
# Test OAuth (dev.example.com)
API_HOST="dev.example.com"

# 1. /api/auth/oauth2/google doit rediriger 302 vers /oauth2/authorization/google
curl -sI "https://$API_HOST/api/auth/oauth2/google"
# Attendu: Location: https://$API_HOST/oauth2/authorization/google

# 2. /oauth2/authorization/google doit rediriger 302 vers Google
curl -sI -L "https://$API_HOST/api/auth/oauth2/google" | head -20
# Attendu: Location: https://accounts.google.com/o/oauth2/...
```

Pour un test complet dans le navigateur : https://$API_HOST/auth/login → cliquer « Sign in with Google ».

## Réseau et CORS

- **Accès principal** : `https://dev.example.com` via `ingress-ip`.
- **CORS** : api-gateway accepte les origines frontend configurées dans `apps/api-gateway/deployment.yaml` (`FRONTEND_ORIGIN`, `SPRING_APPLICATION_JSON`).
- Si le domaine/IP change : mettre à jour DNS + `FRONTEND_ORIGIN` + `SPRING_APPLICATION_JSON`.

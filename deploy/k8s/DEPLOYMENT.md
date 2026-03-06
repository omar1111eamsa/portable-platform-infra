# Déploiement — Prérequis et ordre

> **Voir aussi** : [CHECKLIST.md](CHECKLIST.md) pour la liste des configurations manquantes (DevOps + développeurs).

## Prérequis avant `kubectl apply`

### 0. Réplicas temporairement à 0

Tous les déploiements sont en `replicas: 0` pour vider les serveurs. Remettre à `1` dans les manifests après le nettoyage, puis `kubectl apply -k deploy/k8s/` ou sync ArgoCD.

### 1. Cluster k3s
- 2 nœuds : `backend-vm` (10.0.0.11), `frontend-vm` (IP publique 203.0.113.11)
- Le master k3s sur backend-vm, worker sur frontend-vm
- Noms des nœuds exacts : `backend-vm`, `frontend-vm`
- **Répartition des services** : chaque déploiement a un `nodeSelector` — **backend-vm** : postgres, api-gateway, user-management, payment-service, metamodel ; **frontend-vm** : redis, consul, rabbitmq, frontend, chatbot, predictions-intake, crm-client, kpi-dashboard

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

# Postgres : par défaut dans postgres/secret.yaml (postgres/postgres)
# Pour prod : remplacer par Sealed Secrets ou Vault

# Stripe (payment-service)
kubectl create secret generic stripe-credentials -n myapp \
  --from-literal=STRIPE_API_KEY=sk_test_xxx \
  --from-literal=STRIPE_WEBHOOK_SECRET=whsec_xxx

# Google OAuth (user-management) — REQUIS pour Sign in with Google
# Remplace NGROK_HOST par ton host ngrok (ex: example.ngrok-free.app)
kubectl create secret generic google-oauth-credentials -n myapp \
  --from-literal=GOOGLE_CLIENT_ID=ton-client-id.apps.googleusercontent.com \
  --from-literal=GOOGLE_CLIENT_SECRET=ton-client-secret \
  --from-literal=GOOGLE_REDIRECT_URI=https://NGROK_HOST/login/oauth2/code/google \
  --from-literal=FRONTEND_URL=https://NGROK_HOST

# Pour mettre à jour le secret existant :
# kubectl create secret generic google-oauth-credentials -n myapp \
#   --from-literal=GOOGLE_CLIENT_ID=... \
#   --from-literal=GOOGLE_CLIENT_SECRET=... \
#   --from-literal=GOOGLE_REDIRECT_URI=https://example.ngrok-free.app/login/oauth2/code/google \
#   --from-literal=FRONTEND_URL=https://example.ngrok-free.app \
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
# 3. Infra (postgres, redis, consul, rabbitmq)
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

1. Réinstaller k3s sur les 2 nœuds (backend-vm, frontend-vm)
2. Recréer le namespace et les secrets (ghcr-secret, postgres si besoin)
3. `kubectl apply -k deploy/k8s/`
4. Les PVC (postgres) survivent si le storage class conserve les volumes

---

## Vérification

```bash
kubectl get pods -n myapp
kubectl get ingress -n myapp
curl -s http://203.0.113.11/
curl -s http://203.0.113.11/api/actuator/health
```

### Vérifier OAuth2 Google (Sign in with Google)

```bash
# Test via ngrok (remplace par ton host)
NGROK_HOST="example.ngrok-free.app"

# 1. /api/auth/oauth2/google doit rediriger 302 vers /oauth2/authorization/google
curl -sI -H "ngrok-skip-browser-warning: 1" "https://$NGROK_HOST/api/auth/oauth2/google"
# Attendu: Location: https://$NGROK_HOST/oauth2/authorization/google

# 2. /oauth2/authorization/google doit rediriger 302 vers Google
curl -sI -L -H "ngrok-skip-browser-warning: 1" "https://$NGROK_HOST/api/auth/oauth2/google" | head -20
# Attendu: Location: https://accounts.google.com/o/oauth2/...
```

Pour un test complet dans le navigateur : https://$NGROK_HOST/auth/login → cliquer « Sign in with Google ».

## Réseau et CORS

- **Accès par IP** : `http://203.0.113.11` → Ingress `ingress-ip` route `/api` vers api-gateway, `/` vers frontend
- **CORS** : api-gateway accepte les origines `app.localhost`, `203.0.113.11`, `localhost:3000` (config via `SPRING_APPLICATION_JSON`)
- Si l'IP publique change : mettre à jour `SPRING_APPLICATION_JSON` et `FRONTEND_ORIGIN` dans `apps/api-gateway/deployment.yaml`

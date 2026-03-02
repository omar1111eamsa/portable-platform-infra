# Déploiement — Prérequis et ordre

> **Voir aussi** : [CHECKLIST.md](CHECKLIST.md) pour la liste des configurations manquantes (DevOps + développeurs).

## Prérequis avant `kubectl apply`

### 1. Cluster k3s
- 2 nœuds : `backend-vm` (10.0.0.11), `frontend-vm` (10.0.0.12)
- Le master k3s sur backend-vm, worker sur frontend-vm
- Noms des nœuds exacts : `backend-vm`, `frontend-vm`

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
curl -s http://203.0.113.10/
curl -s http://203.0.113.10/api/actuator/health
```

## Réseau et CORS

- **Accès par IP** : `http://203.0.113.10` → Ingress `ingress-ip` route `/api` vers api-gateway, `/` vers frontend
- **CORS** : api-gateway accepte les origines `app.localhost`, `203.0.113.10`, `localhost:3000` (config via `SPRING_APPLICATION_JSON`)
- Si l'IP publique change : mettre à jour `SPRING_APPLICATION_JSON` et `FRONTEND_ORIGIN` dans `apps/api-gateway/deployment.yaml`

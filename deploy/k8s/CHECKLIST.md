# Checklist — Configuration & backlog restant

> Ce fichier n'est pas la source de vérité runtime. Il sert de backlog pour les points encore à durcir avant une mise en production propre.
>
> Pour l'état réellement déployé, voir:
> - `deploy/docs/ARCHITECTURE-K8S.md`
> - `deploy/docs/API-GATEWAY-BACKENDS.md`
> - `deploy/docs/FLOW-END-TO-END.md`
> - `deploy/docs/METAMODEL-FONCTIONNEMENT.md`

---

## 1. Côté DevOps (ta responsabilité)

### ArgoCD auto-deploy (GH_PAT)

| Action | Détail | Statut |
|--------|--------|--------|
| **GH_PAT** | Vérifier que chaque repo CI qui met à jour `portable-platform-infra` a bien un secret valide (`repo` + `read:packages`). | ☐ |

→ Voir [ARGOCD-AUTODEPLOY.md](../argocd/ARGOCD-AUTODEPLOY.md) pour le détail.

### Secrets à créer manuellement

| Secret | Commande / Action | Statut |
|--------|-------------------|--------|
| **ghcr-secret** | `kubectl create secret docker-registry ghcr-secret -n myapp --docker-server=ghcr.io --docker-username=TON_GITHUB_USER --docker-password=TON_GITHUB_PAT` (PAT scopes: `repo`, `read:packages`) | ☐ |
| **postgres-credentials** | `kubectl create secret generic postgres-credentials -n myapp --from-literal=POSTGRES_USER=... --from-literal=POSTGRES_PASSWORD=... --from-literal=POSTGRES_DB=userdb` | ☐ |
| **rabbitmq-credentials** | `kubectl create secret generic rabbitmq-credentials -n myapp --from-literal=RABBITMQ_DEFAULT_USER=... --from-literal=RABBITMQ_DEFAULT_PASS=... --from-literal=RABBITMQ_DEFAULT_VHOST=/ --from-literal=RABBITMQ_USERNAME=... --from-literal=RABBITMQ_PASSWORD=... --from-literal=RABBITMQ_VHOST=/ --from-literal=RABBITMQ_ADDRESSES=amqp://...@rabbitmq:5672/` | ☐ |
| **chatbot-credentials** | `kubectl create secret generic chatbot-credentials -n myapp --from-literal=LLM_API_KEY=sk-or-VOTRE_CLE_OPENROUTER` — Placeholder OK pour démarrer ; remplacer par la clé OpenRouter réelle. Voir `apps/chatbot/SECRET-SETUP.md` | ☐ |
| **mail-credentials** | `kubectl create secret generic mail-credentials -n myapp --from-literal=SPRING_MAIL_USERNAME=... --from-literal=SPRING_MAIL_PASSWORD=...` | ☐ |
| **auth-credentials** | `kubectl create secret generic auth-credentials -n myapp --from-literal=JWT_SECRET=...` | ☐ |
| **metamodel-db-credentials** | `kubectl create secret generic metamodel-db-credentials -n myapp --from-literal=MYAPP_DB_URL=... --from-literal=AIRFLOW_CONN_POSTGRES_MYAPP=...` | ☐ |

### Configuration à mettre à jour si changement

| Élément | Fichier | Statut |
|--------|---------|--------|
| Domaine frontal (`dev.example.com`) | `apps/api-gateway/deployment.yaml` (FRONTEND_ORIGIN, SPRING_APPLICATION_JSON) | ☐ |
| Noms des nœuds | Prérequis : `backend-vm`, `frontend-vm`, `backend2` | ☐ |

---

## 2. Etat déjà aligné en dev

Ces points ont déjà été corrigés dans les manifests GitOps actuels:

| Point | Etat |
|-------|------|
| `JWT_SECRET` partagé gateway + user-management | Aligné via `auth-credentials/JWT_SECRET` |
| `predictions-intake` via gateway | Aligné via Consul avec enregistrement sur `status.podIP` |
| `execution-engine` | Compatible avec le payload legacy `orders[0].orderId` et le format moderne `signal_id` |
| `metamodel-health-check` | Vérification directe via service Airflow, sans `kubectl exec` |

---

## 3. Côté Développeurs / backlog restant

### user-management

| Variable | Problème | Action | Statut |
|----------|----------|--------|--------|
| **GOOGLE_CLIENT_ID** | Vérifier la cohérence avec les clients Android/iOS/web réellement utilisés | Maintenir les client IDs Google hors code et alignés avec Google Cloud Console | ☐ |
| **GOOGLE_CLIENT_SECRET** | Secret sensible | Rester uniquement côté backend/cluster | ☐ |
| **GOOGLE_REDIRECT_URI** | Dépend du domaine exposé | Doit rester aligné sur `https://dev.example.com/login/oauth2/code/google` tant que ce domaine est utilisé | ☐ |
| **FRONTEND_URL** | Dépend du domaine exposé | Doit rester aligné sur `https://dev.example.com` | ☐ |

### payment-service

| Variable | Problème | Action | Statut |
|----------|----------|--------|--------|
| **STRIPE_API_KEY** | Non configuré | `kubectl create secret generic stripe-credentials -n myapp --from-literal=STRIPE_API_KEY=sk_xxx --from-literal=STRIPE_WEBHOOK_SECRET=whsec_xxx` | ☐ |
| **STRIPE_WEBHOOK_SECRET** | Non configuré | Placeholder OK pour démarrer ; remplacer par les vraies clés Stripe pour les paiements | ☐ |
| **stripe.success.url** / **stripe.cancel.url** | Hardcodés localhost:8082 | Passer en env (URLs frontend) | ☐ |
| **RABBITMQ_USERNAME** / **RABBITMQ_PASSWORD** | À sortir des manifests | Utiliser `rabbitmq-credentials` | ☐ |

### api-gateway

| Variable | Problème | Action | Statut |
|----------|----------|--------|--------|
| **JWT_SECRET** | Déjà aligné en dev | Conserver `auth-credentials/JWT_SECRET` comme source unique | ☑ |

### Base de données

| Point | Action | Statut |
|-------|--------|--------|
| Schéma userdb | Vérifier que userdb contient tables users + payments (ou schémas séparés) | ☐ |

### Google Cloud Console (OAuth)

| Action | Statut |
|--------|--------|
| Créer projet OAuth2 | ☐ |
| Ajouter URI de redirection : `https://dev.example.com/login/oauth2/code/google` | ☐ |
| Récupérer Client ID + Client Secret | ☐ |

---

## 4. Priorité

### Critique (à faire pour que tout fonctionne)

1. ☐ ghcr-secret
2. ☐ Google OAuth (Client ID, Secret, Redirect URI)
3. ☐ Vérifier OAuth en bout en bout (`/api/auth/oauth2/google` -> Google)
4. ☐ Stripe (clés + URLs success/cancel) si paiements utilisés

### Important (sécurité)

5. ☑ JWT_SECRET (api-gateway + user-management, même valeur)
6. ☐ Postgres : mot de passe fort en prod
7. ☐ Sauvegarde PostgreSQL formelle après la récupération WAL
8. ☐ Stabiliser un accès admin durable (Airflow password fixe via secret ou autre méthode)

### Optionnel

9. ☐ HTTPS (certificats + config Traefik)
10. ☐ Domaine personnalisé au lieu de l’IP

---

## ImagePullBackOff

Si user-management ou kpi-dashboard sont en ImagePullBackOff :
- Vérifier que les images existent sur ghcr.io (tags `test-ci-user-management`, `test-ci-kpi`)
- Lancer le CI de chaque repo pour pousser les images
- Ou mettre à jour le deployment avec un tag existant (ex. `latest`, hash de commit)

---

## Références

- [DEPLOYMENT.md](./DEPLOYMENT.md) — Ordre de déploiement
- [README.md](./README.md) — Structure des manifests

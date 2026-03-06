# Checklist — Configuration manquante (DevOps & Développeurs)

> À utiliser pour le suivi des éléments à configurer avant mise en production.

---

## 1. Côté DevOps (ta responsabilité)

### ArgoCD auto-deploy (GH_PAT)

| Action | Détail | Statut |
|--------|--------|--------|
| **GH_PAT** | PAT GitHub (scopes `repo` + `read:packages`) pour que les CI puissent pousser dans portable-platform-infra. À ajouter dans chaque repo : Settings → Secrets → GH_PAT | ☐ |

→ Voir [ARGOCD-AUTODEPLOY.md](../argocd/ARGOCD-AUTODEPLOY.md) pour le détail.

### Secrets à créer manuellement

| Secret | Commande / Action | Statut |
|--------|-------------------|--------|
| **ghcr-secret** | `kubectl create secret docker-registry ghcr-secret -n myapp --docker-server=ghcr.io --docker-username=TON_GITHUB_USER --docker-password=TON_GITHUB_PAT` (PAT scopes: `repo`, `read:packages`) | ☐ |
| **postgres-credentials** | En prod : remplacer postgres/postgres par un mot de passe fort (ou Sealed Secrets / Vault) | ☐ |
| **chatbot-credentials** | `kubectl create secret generic chatbot-credentials -n myapp --from-literal=LLM_API_KEY=sk-or-VOTRE_CLE_OPENROUTER` — Placeholder OK pour démarrer ; remplacer par la clé OpenRouter réelle. Voir `apps/chatbot/SECRET-SETUP.md` | ☐ |

### Configuration à mettre à jour si changement

| Élément | Fichier | Statut |
|--------|---------|--------|
| IP publique (203.0.113.11) | `apps/api-gateway/deployment.yaml` (FRONTEND_ORIGIN, SPRING_APPLICATION_JSON) | ☐ |
| Noms des nœuds | Prérequis : `backend-vm`, `frontend-vm` | ☐ |

---

## 2. Côté Développeurs

### user-management

| Variable | Problème | Action | Statut |
|----------|----------|--------|--------|
| **JWT_SECRET** | Non configuré en k8s | Créer Secret, injecter via env | ☐ |
| **GOOGLE_CLIENT_ID** | Non configuré | Créer app Google Cloud, ajouter au deployment | ☐ |
| **GOOGLE_CLIENT_SECRET** | Non configuré | Idem | ☐ |
| **GOOGLE_REDIRECT_URI** | Actuellement `localhost:8081` | Doit être `https://<ngrok-host>/login/oauth2/code/google` (ex: `https://example.ngrok-free.dev/login/oauth2/code/google`). Doit correspondre à Google Cloud Console. | ☐ |
| **Redirect OAuth hardcodé** | `CustomOAuth2SuccessHandler.java` ligne 155 : `http://localhost:3000` | Remplacer par variable d'environnement `FRONTEND_URL` | ☐ |

### payment-service

| Variable | Problème | Action | Statut |
|----------|----------|--------|--------|
| **STRIPE_API_KEY** | Non configuré | `kubectl create secret generic stripe-credentials -n myapp --from-literal=STRIPE_API_KEY=sk_xxx --from-literal=STRIPE_WEBHOOK_SECRET=whsec_xxx` | ☐ |
| **STRIPE_WEBHOOK_SECRET** | Non configuré | Placeholder OK pour démarrer ; remplacer par les vraies clés Stripe pour les paiements | ☐ |
| **stripe.success.url** / **stripe.cancel.url** | Hardcodés localhost:8082 | Passer en env (URLs frontend) | ☐ |
| **RABBITMQ_USERNAME** / **RABBITMQ_PASSWORD** | Déjà en k8s (guest/guest) | — | ✓ |

### api-gateway

| Variable | Problème | Action | Statut |
|----------|----------|--------|--------|
| **JWT_SECRET** | Valeur par défaut hardcodée | Créer Secret, injecter (même valeur que user-management) | ☐ |

### Base de données

| Point | Action | Statut |
|-------|--------|--------|
| Schéma userdb | Vérifier que userdb contient tables users + payments (ou schémas séparés) | ☐ |

### Google Cloud Console (OAuth)

| Action | Statut |
|--------|--------|
| Créer projet OAuth2 | ☐ |
| Ajouter URI de redirection : `https://<ngrok-host>/login/oauth2/code/google` (ex: `https://example.ngrok-free.dev/login/oauth2/code/google`) | ☐ |
| Récupérer Client ID + Client Secret | ☐ |

---

## 3. Priorité

### Critique (à faire pour que tout fonctionne)

1. ☐ ghcr-secret
2. ☐ Google OAuth (Client ID, Secret, Redirect URI)
3. ☐ CustomOAuth2SuccessHandler — rendre FRONTEND_URL configurable
4. ☐ Stripe (clés + URLs success/cancel) si paiements utilisés

### Important (sécurité)

5. ☐ JWT_SECRET (api-gateway + user-management, même valeur)
6. ☐ Postgres : mot de passe fort en prod

### Optionnel

7. ☐ HTTPS (certificats + config Traefik)
8. ☐ Domaine personnalisé au lieu de l’IP

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

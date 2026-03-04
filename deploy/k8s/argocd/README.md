# ArgoCD Ingress — accès UI via domaine

## URL d'accès

- **https://example.ngrok-free.app/argocd**
- Header requis (ngrok): `ngrok-skip-browser-warning: 1`

## Prérequis: configurer ArgoCD pour le reverse proxy

Exécuter une fois avant de déployer l'Ingress:

```bash
# Activer le mode insecure (TLS terminé côté Ingress)
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'

# Configurer le base path /argocd
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.basehref":"/argocd"}}'

# Redémarrer le serveur ArgoCD
kubectl rollout restart deployment argocd-server -n argocd
```

## Mot de passe admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

Utilisateur par défaut: `admin`

# ArgoCD Ingress — accès UI via domaine

## URL d'accès

- **https://example.ngrok-free.app/argocd**
- Header requis (ngrok): `ngrok-skip-browser-warning: 1`

## Prérequis: configurer ArgoCD pour le reverse proxy

Exécuter **une fois** (déjà fait si l'Ingress a été appliqué manuellement):

```bash
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true","server.basehref":"/argocd","server.rootpath":"/argocd"}}'
kubectl rollout restart deployment argocd-server -n argocd
```

## Mot de passe admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

Utilisateur par défaut: `admin`

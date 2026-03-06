# ArgoCD Ingress — accès UI via domaine

## URL d'accès

- **https://dev.example.com/argocd**
- Si tunnel ngrok : header `ngrok-skip-browser-warning: 1` ; avec dev.example.com optionnel.

## Prérequis: configurer ArgoCD pour le reverse proxy

Exécuter **une fois** (déjà fait si l'Ingress a été appliqué manuellement):

```bash
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true","server.basehref":"/argocd","server.rootpath":"/argocd"}}'
kubectl rollout restart deployment argocd-server -n argocd
```

## Si argocd-server est en CrashLoopBackOff (probes trop courtes)

Exécuter une fois pour augmenter les délais des probes (liveness/readiness):

```bash
kubectl patch deployment argocd-server -n argocd --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value": 60},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 30}
]'
```

Puis attendre ~1 min que le pod repasse en Running.

## Mot de passe admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

Utilisateur par défaut: `admin`

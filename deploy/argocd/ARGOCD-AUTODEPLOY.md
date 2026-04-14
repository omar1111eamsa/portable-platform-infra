# ArgoCD — Auto-Deploy Configuration

## Overview

ArgoCD monitors the `test-argocd` branch of `portable-platform-infra` and automatically syncs the cluster on every commit to that branch.

- **ArgoCD URL**: `https://dev.example.com/argocd`
- **Application name**: `myapp`
- **Destination namespace**: `myapp`
- **Sync policy**: Automated (self-healing, prune enabled)

## How It Works

1. A service's GitHub Actions CI pipeline builds a Docker image and pushes it to GHCR.
2. CI updates the `image:` tag in the relevant deployment manifest in this repository on the `test-argocd` branch.
3. ArgoCD detects the commit within its polling interval (default: 3 minutes) and applies the changes.

Manual sync can be triggered via the ArgoCD UI or CLI:

```bash
argocd app sync myapp
```

## Application Definition

The ArgoCD Application manifest is at `deploy/argocd/application-myapp.yaml`.

Key fields:

```yaml
source:
  repoURL: https://github.com/MyApp/portable-platform-infra
  targetRevision: test-argocd
  path: deploy/k8s
destination:
  server: https://kubernetes.default.svc
  namespace: myapp
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

## Adding a New Service

1. Create the deployment manifest under `deploy/k8s/apps/<service-name>/`.
2. Add the manifest path to `deploy/k8s/kustomization.yaml`.
3. Commit to `test-argocd`. ArgoCD will pick up and deploy the new workload.

## Credentials

The ArgoCD initial admin password is stored in the cluster:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

## Troubleshooting

| Symptom | Action |
|---|---|
| `OutOfSync` but no manifest change | Run `argocd app sync myapp --force` |
| Sync fails on image pull | Verify the GHCR image tag exists and the pull secret is valid |
| Application stuck in `Progressing` | Check pod events: `kubectl describe pod -n myapp <pod>` |
| ArgoCD UI unreachable | Check Traefik ingress and the `argocd-server` pod |

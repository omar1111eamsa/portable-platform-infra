# ArgoCD — Installation and Ingress

## Installation

ArgoCD is installed from the official upstream manifest (`install.yaml`) pinned to v2.14.10+. This version resolves the `/argocd/argocd/applications` redirect issue after local login (upstream issue #20790).

The `argocd-cmd-params-patch.yaml` configures ArgoCD to operate behind a reverse proxy at path `/argocd`:

```yaml
server.insecure: "true"
server.basehref: /argocd
server.rootpath: /argocd
```

## Access

- **URL**: `https://dev.example.com/argocd`
- **Username**: `admin`
- **Password**: Retrieved from the cluster secret (see below)

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

## TLS

TLS is terminated at Traefik. ArgoCD itself runs in insecure mode (`--insecure`). The Traefik ingress handles the HTTPS certificate for `dev.example.com`.

## Application

The `myapp` ArgoCD Application is defined in `deploy/argocd/application-myapp.yaml`. It monitors the `test-argocd` branch of this repository and applies `deploy/k8s` via Kustomize.

Auto-sync is enabled with pruning and self-healing.

## Verify

```bash
kubectl get application myapp -n argocd \
  -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision"
```

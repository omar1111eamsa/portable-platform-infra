# ArgoCD Auto-Deploy Setup

When a service (Front-end, user-management, api-gateway, etc.) pushes to its CI branch, the workflow:

1. Builds and pushes a Docker image to GHCR
2. Clones `portable-platform-infra` (branch `test-argocd`)
3. Updates the deployment YAML with the new image tag
4. Commits and pushes the change
5. ArgoCD detects the change and syncs the cluster

## Required: `GH_PAT` Secret

Step 2–4 requires a **GitHub Personal Access Token** with write access to `portable-platform-infra`.

### 1. Create a Personal Access Token

1. Go to [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. Generate a new token (classic)
3. Grant scope: **`repo`** (full control of private repositories)
4. Copy the token (you won’t see it again)

### 2. Add `GH_PAT` in each app repo

Add the secret in **Settings → Secrets and variables → Actions** for:

| Repository | Branch CI uses |
|------------|----------------|
| MyApp/Front-end | `test-ci-frontend` |
| MyApp/Backend-User-management-and-subscripption | `test-ci-user-management` |
| MyApp/Backend-api-gateway | (configure as needed) |
| MyApp/Backend-payment-service | (configure as needed) |
| MyApp/Backend-KPI-Dashboard-notifications | (configure as needed) |
| MyApp/Backend-chatbot | (configure as needed) |
| MyApp/Backend-predictions-intake-service | (configure as needed) |
| MyApp/Backend-crm-client | (configure as needed) |

- Secret name: **`GH_PAT`**
- Value: the token you created

### 3. Ensure the ArgoCD Application exists

Apply the ArgoCD Application so it watches the `test-argocd` branch:

```bash
kubectl apply -f deploy/argocd/application-myapp.yaml
```

The Application uses `syncPolicy.automated`, so it syncs automatically when the Git repo changes.

### 4. Verify the flow

1. Push a commit to `test-ci-frontend` (or `test-ci-user-management`)
2. Check GitHub Actions: build and push should succeed, and the "Update manifests and push to test-argocd" step should complete
3. In ArgoCD, the `myapp` app should sync and roll out the new image

If `GH_PAT` is missing, the workflow will fail with a clear error asking you to add it.

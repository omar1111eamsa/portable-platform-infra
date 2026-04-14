# Chatbot — Secret Configuration

The `chatbot-credentials` secret is not stored in this repository. It must be created manually to avoid overwriting the API key on each ArgoCD sync.

## Create or Update the Secret

```bash
kubectl create secret generic chatbot-credentials \
  -n myapp \
  --from-literal=LLM_API_KEY=<your_openrouter_key> \
  --dry-run=client -o yaml | kubectl apply -f -
```

The secret is referenced by `deployment.yaml` as the `LLM_API_KEY` environment variable.

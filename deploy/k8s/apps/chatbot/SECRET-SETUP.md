# Chatbot — Configuration du secret LLM

Le secret `chatbot-credentials` **n'est pas** dans le dépôt (pour ne pas écraser ta clé à chaque sync ArgoCD).

## Créer / mettre à jour le secret

```bash
kubectl create secret generic chatbot-credentials -n myapp \
  --from-literal=LLM_API_KEY=sk-or-TA_CLE_OPENROUTER \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/chatbot -n myapp
```

Remplacer `sk-or-TA_CLE_OPENROUTER` par ta clé réelle (sans espace).

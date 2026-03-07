# URLs pour les testeurs — MyApp

## Option 1 : Accès via domaine (recommandé)

**Frontend :** https://dev.example.com/

**HTTPS (recommandé pour OAuth) :** https://dev.example.com  
**ArgoCD :** https://dev.example.com/argocd

| Service | URL |
|---------|-----|
| **Frontend** | https://dev.example.com/ |
| **API** | https://dev.example.com/api/ |
| **Auth** | https://dev.example.com/auth/ |
| **Swagger** | https://dev.example.com/swagger-ui.html |

---

## Option 2 : Accès direct par IP (debug uniquement)

Utiliser l'IP publique uniquement pour debug réseau (hors OAuth).

**URLs :**

| Service | URL |
|---------|-----|
| Frontend | http://203.0.113.11 |
| API via gateway | http://203.0.113.11/api |
| Chatbot via gateway | http://203.0.113.11/chatbot |

---

## Prérequis

- **Ports ouverts** : 80 (et 443 si HTTPS) sur la VM frontend (203.0.113.11)
- Le cluster k3s doit être déployé et les services Running

### Ouvrir le firewall GCP (si nécessaire)

```bash
gcloud compute firewall-rules create allow-http-https \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80,tcp:443 \
  --source-ranges=0.0.0.0/0
```

---

## Vérifier la connectivité

```bash
# Test frontend
curl -k -s -o /dev/null -w "%{http_code}" https://dev.example.com/

# Test API
curl -k -s https://dev.example.com/api/actuator/health
```

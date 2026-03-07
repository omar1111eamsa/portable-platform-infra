# URLs pour les testeurs — MyApp

## Option 1 : Accès direct par IP (aucune config)

**Frontend (IP publique frontend-vm) :** http://203.0.113.11/

**HTTPS (recommandé pour OAuth) :** https://dev.example.com et https://dev.example.com  
**ArgoCD :** https://dev.example.com/argocd

| Service | URL |
|---------|-----|
| **Frontend** | http://203.0.113.11/ |
| **API** | http://203.0.113.11/api/ |
| **Auth** | http://203.0.113.11/auth/ |
| **Swagger** | http://203.0.113.11/swagger-ui.html |

---

## Option 2 : Accès par hostname (recommandé)

Configurer le DNS (ou fichier hosts) uniquement pour `dev.example.com` vers `203.0.113.11`.

**URLs :**

| Service | URL |
|---------|-----|
| Frontend | https://dev.example.com |
| API via gateway | https://dev.example.com/api |
| Chatbot via gateway | https://dev.example.com/chatbot |

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
curl -s -o /dev/null -w "%{http_code}" http://203.0.113.11/

# Test API
curl -s http://203.0.113.11/api/actuator/health
```

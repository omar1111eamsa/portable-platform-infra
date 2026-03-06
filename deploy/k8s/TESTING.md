# URLs pour les testeurs — MyApp

## Option 1 : Accès direct par IP (aucune config)

**Frontend (IP publique frontend-vm) :** http://203.0.113.11/

**HTTPS (recommandé pour OAuth) :** https://dev.example.com et https://api.example.com  
**ArgoCD :** https://dev.example.com/argocd

| Service | URL |
|---------|-----|
| **Frontend** | http://203.0.113.11/ |
| **API** | http://203.0.113.11/api/ |
| **Auth** | http://203.0.113.11/auth/ |
| **Swagger** | http://203.0.113.11/swagger-ui.html |

---

## Option 2 : Accès par hostnames (avec fichier hosts)

Ajouter dans `/etc/hosts` (Linux/Mac) ou `C:\Windows\System32\drivers\etc\hosts` (Windows) :

```
203.0.113.11 api.localhost app.localhost payment.localhost users.localhost crm.localhost chatbot.localhost predictions.localhost kpi.localhost
```

**URLs :**

| Service | URL |
|---------|-----|
| Frontend | http://app.localhost |
| API Gateway | http://api.localhost |
| Payment | http://payment.localhost |
| Users | http://users.localhost |
| CRM | http://crm.localhost |
| Chatbot | http://chatbot.localhost |
| Predictions | http://predictions.localhost |
| KPI Dashboard | http://kpi.localhost |

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

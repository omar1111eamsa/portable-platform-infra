# Metamodel-orchestration (Airflow)

- **Image** : `Metamodel-orschestation-airflow` (Apache Airflow API server, port 8080).
- **Pas exposé via l’API Gateway** : service interne (health `/health`).
- **Métadonnées Airflow** : **SQLite** (`airflow.db` dans le conteneur, défaut airflow.cfg).
- **Nœud** : **frontend-vm** (nodeSelector). Replicas **0** par défaut tant que DiskPressure sur le nœud.

## Si le pod est évincé (DiskPressure)

1. **Libérer le disque** (SSH sur le nœud) : **uniquement** `sudo crictl rmi --prune`  
   (supprime les images inutilisées ; ne pas lancer `crictl rmp -a` — ça tente de supprimer tous les pods, y compris les running.)
2. Vérifier : `kubectl describe node frontend-vm | grep -A5 Conditions`
3. Réactiver : `kubectl scale deployment metamodel-orchestration -n myapp --replicas=1`

## Arrêter

`kubectl scale deployment metamodel-orchestration -n myapp --replicas=0`

## Ressources

- Request: 384Mi, limit: 768Mi.

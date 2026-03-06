# Metamodel-orchestration (Airflow)

- **Image** : `Metamodel-orschestation-airflow` (Apache Airflow API server, port 8080).
- **Pas exposé via l’API Gateway** : service interne (health `/health`, pas de route dans le gateway).
- **RAM** : gourmand ; déployé uniquement sur **backend-vm**. api-gateway et payment-service ont été déplacés sur frontend-vm pour libérer de la RAM sur backend et éviter les evictions.

## Déploiement contrôlé

- **replicas: 0** par défaut dans le manifest. Pour lancer le service :
  ```bash
  kubectl scale deployment metamodel-orchestration -n myapp --replicas=1
  ```
- Surveiller la RAM sur backend-vm : `kubectl top node backend-vm -n myapp`
- Pour arrêter : `kubectl scale deployment metamodel-orchestration -n myapp --replicas=0`

## Ressources

- Request: 384Mi, limit: 768Mi (pour borner la consommation et éviter de saturer le nœud).

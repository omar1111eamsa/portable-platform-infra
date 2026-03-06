# Metamodel-orchestration (Airflow)

- **Image** : `Metamodel-orschestation-airflow` (Apache Airflow API server, port 8080).
- **Pas exposé via l’API Gateway** : service interne (health `/health`, pas de route dans le gateway).
- **Nœud** : **frontend-vm** (backend-vm a DiskPressure → éviction des pods ; frontend-vm n’a pas de pression disque).

## Déploiement

- replicas: 1 par défaut, nodeSelector: frontend-vm.
- Pour arrêter : `kubectl scale deployment metamodel-orchestration -n myapp --replicas=0`
- Surveiller : `kubectl top node frontend-vm` et `kubectl top pod -l app=metamodel-orchestration -n myapp`

## Ressources

- Request: 384Mi, limit: 768Mi.

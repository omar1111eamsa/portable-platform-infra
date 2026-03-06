# Metamodel-orchestration (Airflow)

- **Image** : `Metamodel-orschestation-airflow` (Apache Airflow API server, port 8080).
- **Pas exposé via l’API Gateway** : service interne (health `/health`).
- **Nœud** : **frontend-vm** (quand activé). replicas **0** tant que DiskPressure sur les nœuds.

## Si le pod est évincé (DiskPressure)

1. Libérer le disque sur le nœud concerné (SSH) : `sudo crictl rmi --prune` puis `sudo crictl rmp -a`
2. Vérifier : `kubectl describe node backend-vm | grep -A5 Conditions`
3. Réactiver si besoin : `kubectl scale deployment metamodel-orchestration -n myapp --replicas=1`

## Arrêter

`kubectl scale deployment metamodel-orchestration -n myapp --replicas=0`

## Ressources

- Request: 384Mi, limit: 768Mi.

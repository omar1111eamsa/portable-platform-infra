# Metamodel-orchestration (Airflow)

- **Image** : `Metamodel-orschestation-airflow` (Apache Airflow API server, port 8080).
- **Pas exposé via l’API Gateway** : service interne (health `/health`).
- **Nœud** : **frontend-vm** (nodeSelector). replicas: **0** par défaut tant que DiskPressure sur les nœuds.

## Activer le déploiement (après libération disque)

Les pods sont évincés si le nœud a **DiskPressure**. Avant de passer à replicas 1 :

1. **Libérer le disque sur frontend-vm** (SSH sur la VM) :
   ```bash
   sudo crictl rmi --prune
   sudo crictl rmp -a
   ```
2. Vérifier que le nœud n’a plus de pression : `kubectl describe node frontend-vm | grep -A5 Conditions`
3. Activer : `kubectl scale deployment metamodel-orchestration -n myapp --replicas=1`
4. Ou mettre `replicas: 1` dans ce manifest et pousser (ArgoCD appliquera).

## Arrêter

`kubectl scale deployment metamodel-orchestration -n myapp --replicas=0`

## Ressources

- Request: 384Mi, limit: 768Mi.

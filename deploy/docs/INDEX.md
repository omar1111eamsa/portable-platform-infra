# Documentation — portable-platform-infra

| Document | Description |
|----------|-------------|
| [ARCHITECTURE-K8S.md](ARCHITECTURE-K8S.md) | Architecture cluster et rôle de chaque fichier K8s |
| [FRONTEND-API-GATEWAY.md](FRONTEND-API-GATEWAY.md) | Relation frontend ↔ api-gateway (env, réseau, tests) |
| [API-GATEWAY-BACKENDS.md](API-GATEWAY-BACKENDS.md) | Routes API Gateway ↔ backends (paths, services K8s, Consul) |
| [ENDPOINTS-CATALOG.md](ENDPOINTS-CATALOG.md) | Inventaire complet des endpoints (source, gateway, ingress, runtime) |
| [FLOW-END-TO-END.md](FLOW-END-TO-END.md) | Flux cible complet frontend → API → metamodel → execution |
| [DB-ARCHITECTURE.md](DB-ARCHITECTURE.md) | Architecture Postgres et services consommateurs |
| [METAMODEL-FONCTIONNEMENT.md](METAMODEL-FONCTIONNEMENT.md) | Détail du fonctionnement metamodel (Airflow, DAG, DB, modules, exploitation) |
| [TESTERS-GUIDE.md](../TESTERS-GUIDE.md) | Guide testeurs : architecture, APIs, cURL, pentest |
| [k8s/README.md](../k8s/README.md) | Kubernetes : structure, kustomize |
| [k8s/DEPLOYMENT.md](../k8s/DEPLOYMENT.md) | Procédure de déploiement |
| [k8s/CHECKLIST.md](../k8s/CHECKLIST.md) | Checklist config manquantes |
| [k8s/argocd/README.md](../k8s/argocd/README.md) | ArgoCD Ingress (URL, mot de passe admin) |
| [argocd/ARGOCD-AUTODEPLOY.md](../argocd/ARGOCD-AUTODEPLOY.md) | ArgoCD auto-deploy (GH_PAT, branches) |
| [k8s/OAUTH2-FIX.md](../k8s/OAUTH2-FIX.md) | OAuth2 Google (dev.example.com) — déploiement et vérification |

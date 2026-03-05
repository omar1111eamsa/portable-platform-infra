# Guide de setup complet — Cluster MyApp

Ce guide permet de déployer le cluster k3s depuis zéro (VMs réinitialisées) avec un minimum de commandes.

---

## Architecture

| Composant   | VM            | Rôle                                    |
|-------------|---------------|-----------------------------------------|
| backend-vm  | 10.0.0.11     | k3s server (master), pas d’IP externe   |
| frontend-vm | 203.0.113.11 | k3s agent (worker), ngrok, IP publique  |

**Accès SSH** : `frontend-vm` a l’IP publique → ProxyJump pour atteindre `backend-vm`.

---

## Prérequis

- SSH configuré : clé `~/.ssh/myapp_vms`, accès à `hodeconlimited@203.0.113.11`
- Ansible installé
- `kubectl` et `kustomize` (optionnel, fournis par k3s)
- Compte ngrok + authtoken

---

## Parcours minimal

### 1. Préparer le Kubeconfig

```bash
mkdir -p ~/.kube
```

Créer `~/.kube/myapp-k3s.yaml` (à remplir après l’étape 2) :

```yaml
apiVersion: v1
kind: Config
clusters:
  - cluster:
      server: https://127.0.0.1:16443
      insecure-skip-tls-verify: true
    name: myapp
contexts:
  - context:
      cluster: myapp
      user: default
    name: myapp
current-context: myapp
users:
  - name: default
    user:
      # À remplir après copie de /etc/rancher/k3s/k3s.yaml du serveur
```

### 2. Installer le cluster (Ansible)

```bash
cd ansible

# Créer group_vars pour le token ngrok (requis)
mkdir -p group_vars
echo "ngrok_authtoken: votre_authtoken_ngrok" > group_vars/k3s_agents.yml
# Ou: export NGROK_AUTHTOKEN=xxx; echo "ngrok_authtoken: $NGROK_AUTHTOKEN" > group_vars/k3s_agents.yml

# Lancer le playbook
ansible-playbook -i inventory.yml playbook.yml
```

Récupérer le kubeconfig du serveur :

```bash
ssh -i ~/.ssh/myapp_vms -J hodeconlimited@203.0.113.11 hodeconlimited@10.0.0.11 \
  "sudo cat /etc/rancher/k3s/k3s.yaml" | sed 's/127.0.0.1/127.0.0.1/' | sed 's/6443/16443/' > ~/.kube/myapp-k3s.yaml
```

### 3. Tunnel kubectl (SSH)

```bash
cd deploy/k8s/scripts
./start-kubectl-tunnel.sh --background
sleep 10
export KUBECONFIG=~/.kube/myapp-k3s.yaml
kubectl get nodes
```

### 4. Créer le secret GHCR (images privées)

```bash
kubectl create secret docker-registry ghcr-secret -n myapp \
  --docker-server=ghcr.io \
  --docker-username=VOTRE_GITHUB_USER \
  --docker-password=VOTRE_PAT
```

### 5. Activer infra + apps

Dans `deploy/k8s/kustomization.yaml`, décommenter `infra` et `apps`, et mettre `replicas: 1` dans les deployments.

### 6. Appliquer les manifests avec le domaine ngrok

```bash
./apply-with-ngrok-domain.sh
```

Si ngrok n’est pas démarré ou que le domaine doit être forcé :

```bash
./apply-with-ngrok-domain.sh --domain example.ngrok-free.app
```

### 7. Secret Google OAuth (pour Sign in with Google)

```bash
NGROK_DOMAIN="example.ngrok-free.app"  # ou celui affiché par apply-with-ngrok-domain.sh
kubectl create secret generic google-oauth-credentials -n myapp \
  --from-literal=GOOGLE_CLIENT_ID=xxx \
  --from-literal=GOOGLE_CLIENT_SECRET=xxx \
  --from-literal=GOOGLE_REDIRECT_URI=https://${NGROK_DOMAIN}/login/oauth2/code/google \
  --from-literal=FRONTEND_URL=https://${NGROK_DOMAIN}
```

---

## Récapitulatif des commandes (copier-coller)

```bash
# 1. Ansible (depuis le repo)
cd ansible
ansible-playbook -i inventory.yml playbook.yml

# 2. Kubeconfig
ssh -i ~/.ssh/myapp_vms -J hodeconlimited@203.0.113.11 hodeconlimited@10.0.0.11 \
  "sudo cat /etc/rancher/k3s/k3s.yaml" | sed 's/6443/16443/' > ~/.kube/myapp-k3s.yaml

# 3. Tunnel
cd ../deploy/k8s/scripts
./start-kubectl-tunnel.sh --background
export KUBECONFIG=~/.kube/myapp-k3s.yaml

# 4. Secret GHCR
kubectl create secret docker-registry ghcr-secret -n myapp --docker-server=ghcr.io --docker-username=USER --docker-password=PAT

# 5. Appliquer (après avoir décommenté infra+apps dans kustomization.yaml)
./apply-with-ngrok-domain.sh
```

---

## Personnalisation

| Variable    | Fichier          | Rôle                                  |
|------------|-------------------|----------------------------------------|
| `JUMP_HOST`| start-kubectl-tunnel.sh | IP publique du frontend          |
| `BACKEND_HOST` | idem          | IP backend (réseau interne)            |
| `SSH_USER` | idem              | Utilisateur SSH                       |
| `SSH_KEY`  | idem              | Clé privée SSH                        |
| `ngrok_authtoken` | group_vars/k3s_agents.yml | Token ngrok                    |

---

## Prochaines étapes (brainstorm)

- Allocation des ressources (CPU/RAM) par service
- Répartition des apps entre backend-vm et frontend-vm

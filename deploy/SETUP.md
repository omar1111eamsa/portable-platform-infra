# Guide de setup complet — Cluster MyApp

Ce guide permet de déployer le cluster k3s depuis zéro (VMs réinitialisées) avec un minimum de commandes.

---

## Architecture

| Composant   | VM            | Rôle                                    |
|-------------|---------------|-----------------------------------------|
| backend-vm  | 10.0.0.11     | k3s server (control-plane), pas d’IP externe |
| frontend-vm | IP publique réservée + 10.0.0.12 | k3s agent (worker), IP publique |
| backend2    | 10.0.0.13     | k3s agent (worker), accès via ProxyJump |

**DNS** : dev.example.com → IP publique réservée de `frontend-vm`. **Accès SSH** : frontend-vm = jumphost ; backend-vm et backend2 via ProxyJump.

## Infra base (Terraform — GCP)

Le socle Terraform dans [`../terraform`](../terraform) recrée la même logique réseau sur **GCP** :

- VPC `myapp-vpc` + subnet `10.10.0.0/24`
- IPs privées fixes :
  - `backend-vm` = `10.0.0.11`
  - `frontend-vm` = `10.0.0.12`
  - `backend2` = `10.0.0.13`
- IP publique **statique** seulement pour `frontend-vm`
- Firewall :
  - SSH public vers les VMs (n’atteint de l’extérieur que le jumphost, seul avec une IP publique)
  - HTTP/HTTPS depuis Internet
  - trafic interne k3s entre les 3 nœuds

Appliquer l'infra avant Ansible :

```bash
cd ../terraform
cp terraform.tfvars.example terraform.tfvars
# Renseigner project_id et ssh_public_key
terraform init
terraform apply
```

Récupérer ensuite l’IP publique du jumphost :

```bash
terraform output -raw frontend_public_ip
```

---

## Prérequis

- SSH configuré : clé `~/.ssh/myapp_vms`, accès à `myapp@<frontend_public_ip>`
- Ansible installé
- `kubectl` et `kustomize` (optionnel, fournis par k3s)
---

## Parcours minimal

### 0. Bootstrap automatique (recommandé)

```bash
cp deploy/k8s/secrets.env.example deploy/k8s/secrets.env
# éditer deploy/k8s/secrets.env avec les vraies valeurs

./ansible/bootstrap-cluster.sh
```

Cette commande enchaîne Ansible + kubeconfig + tunnel + secrets + `kubectl apply -k deploy/k8s`.

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

# Lancer le playbook
ansible-playbook -i inventory.yml playbook.yml
```

Récupérer le kubeconfig du serveur :

```bash
ssh -i ~/.ssh/myapp_vms -J myapp@<frontend_public_ip> myapp@10.0.0.11 \
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

Les manifests `infra` + `apps` sont déjà inclus dans `deploy/k8s/kustomization.yaml`.
Le chemin recommandé reste `./ansible/bootstrap-cluster.sh` (création secrets + apply global).

### 6. ArgoCD (optionnel)

ArgoCD sync automatiquement depuis la branche `test-argocd`. Voir [argocd/ARGOCD-AUTODEPLOY.md](argocd/ARGOCD-AUTODEPLOY.md).

### 7. Appliquer les manifests (dev.example.com)

```bash
./apply-with-domain.sh
```

### 8. Secret Google OAuth (pour Sign in with Google)

```bash
kubectl create secret generic google-oauth-credentials -n myapp \
  --from-literal=GOOGLE_CLIENT_ID=xxx \
  --from-literal=GOOGLE_CLIENT_SECRET=xxx \
  --from-literal=GOOGLE_REDIRECT_URI=https://dev.example.com/login/oauth2/code/google \
  --from-literal=FRONTEND_URL=https://dev.example.com
```

---

## Récapitulatif des commandes (copier-coller)

```bash
# 1. Ansible (depuis le repo)
cd ansible
ansible-playbook -i inventory.yml playbook.yml

# 2. Kubeconfig
ssh -i ~/.ssh/myapp_vms -J myapp@<frontend_public_ip> myapp@10.0.0.11 \
  "sudo cat /etc/rancher/k3s/k3s.yaml" | sed 's/6443/16443/' > ~/.kube/myapp-k3s.yaml

# 3. Tunnel
cd ../deploy/k8s/scripts
./start-kubectl-tunnel.sh --background
export KUBECONFIG=~/.kube/myapp-k3s.yaml

# 4. Secret GHCR
kubectl create secret docker-registry ghcr-secret -n myapp --docker-server=ghcr.io --docker-username=USER --docker-password=PAT

# 5. Appliquer
./apply-with-domain.sh
```

---

## Personnalisation

| Variable    | Fichier          | Rôle                                  |
|------------|-------------------|----------------------------------------|
| `JUMP_HOST`| start-kubectl-tunnel.sh | IP publique du frontend          |
| `BACKEND_HOST` | idem          | IP backend (réseau interne)            |
| `SSH_USER` | idem              | Utilisateur SSH                       |
| `SSH_KEY`  | idem              | Clé privée SSH                        |

---

## Prochaines étapes (brainstorm)

- Allocation des ressources (CPU/RAM) par service
- Répartition des apps entre backend-vm et frontend-vm

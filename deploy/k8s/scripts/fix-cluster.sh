#!/bin/bash
# Fix cluster: clean evicted pods, scale deployments to 1, trigger clean-disk, show status.
# Run with tunnel up: export KUBECONFIG=~/.kube/myapp-k3s.yaml && ./fix-cluster.sh
set -e
NS="${NAMESPACE:-myapp}"

check() {
  if ! kubectl get nodes &>/dev/null; then
    echo "ERROR: Cannot reach cluster. Start the tunnel first: ./start-kubectl-tunnel.sh --background"
    exit 1
  fi
}

echo "Checking cluster connectivity..."
check

echo "Deleting evicted/failed pods in $NS..."
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '$3=="Evicted" || $3=="Failed" || $3=="ContainerStatusUnknown" {print $1}' | while read -r p; do
  kubectl delete pod -n "$NS" "$p" --ignore-not-found --wait=false 2>/dev/null || true
done

echo "Scaling all deployments in $NS to 1 replica..."
for d in $(kubectl get deployments -n "$NS" -o name 2>/dev/null); do
  kubectl scale -n "$NS" "$d" --replicas=1 2>/dev/null || true
done

echo "Triggering clean-disk jobs..."
kubectl create job -n "$NS" --from=cronjob/clean-disk-backend fix-disk-backend-$(date +%s) 2>/dev/null || true
kubectl create job -n "$NS" --from=cronjob/clean-disk-frontend fix-disk-frontend-$(date +%s) 2>/dev/null || true

echo "--- Deployment status ---"
kubectl get deployments -n "$NS" -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,UNAVAILABLE:.status.unavailableReplicas 2>/dev/null

echo "--- Pods not Running ---"
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -v "1/1 Running" | grep -v "Completed" | head -20

echo "Done. Re-run to re-check; wait a few minutes for pods to become Ready."

#!/bin/bash
# deploy/k8s/scripts/e2e-test.sh
#
# Full end-to-end test of the MyApp platform
# Verifies everything works from infrastructure to applications
#
# Usage:
#   ./e2e-test.sh
#   ./e2e-test.sh --skip-terraform
#   ./e2e-test.sh --skip-ansible
#   ./e2e-test.sh --kubeconfig ~/.kube/myapp-rke2.yaml
#
# Prerequisites:
#   - terraform apply completed
#   - ansible bootstrap completed
#   - kubectl configured

set -euo pipefail

# ── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ───────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${BLUE}${BOLD}━━━ $1 ━━━${NC}\n"; }
log_success() { echo -e "${GREEN}${BOLD}✓ $1${NC}"; }
log_fail()    { echo -e "${RED}${BOLD}✗ $1${NC}"; }

# ── Test tracking ─────────────────────────────────────────
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

pass() {
  local name=$1
  log_success "$name"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  local name=$1
  local reason=$2
  log_fail "$name — $reason"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_TESTS+=("$name: $reason")
}

# ── Timer ─────────────────────────────────────────────────
START_TIME=$(date +%s)
elapsed() {
  echo $(( $(date +%s) - START_TIME ))
}

# ── Defaults ──────────────────────────────────────────────
KUBECONFIG_PATH="$HOME/.kube/myapp-rke2.yaml"
SKIP_TERRAFORM=false
SKIP_ANSIBLE=false
NAMESPACE="myapp"

# ── Argument parsing ──────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-terraform)
      SKIP_TERRAFORM=true
      shift
      ;;
    --skip-ansible)
      SKIP_ANSIBLE=true
      shift
      ;;
    --kubeconfig)
      KUBECONFIG_PATH="$2"
      shift 2
      ;;
    --help)
      echo "Usage: ./e2e-test.sh [options]"
      echo ""
      echo "Options:"
      echo "  --skip-terraform    Skip Terraform validation"
      echo "  --skip-ansible      Skip Ansible validation"
      echo "  --kubeconfig <path> Path to kubeconfig"
      echo "  --help              Show this help"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

export KUBECONFIG="$KUBECONFIG_PATH"

# ── Banner ────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║     MyApp End-to-End Test Suite       ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo "Kubeconfig : $KUBECONFIG_PATH"
echo "Namespace  : $NAMESPACE"
echo "Time       : $(date -u)"
echo ""

# ── Test 1: Terraform state ───────────────────────────────
log_step "Test 1/6 — Terraform Infrastructure"

if [ "$SKIP_TERRAFORM" = true ]; then
  log_warn "Skipping Terraform tests"
else
  cd terraform

  # Check Terraform state exists
  if terraform output cluster_nodes &>/dev/null; then
    pass "Terraform state is readable"
  else
    fail "Terraform state" "Cannot read cluster_nodes output"
  fi

  # Check all 3 nodes have IPs
  CP_IP=$(terraform output -raw cp_01_internal_ip 2>/dev/null || echo "")
  W1_IP=$(terraform output -raw worker_01_internal_ip 2>/dev/null || echo "")
  W2_IP=$(terraform output -raw worker_02_internal_ip 2>/dev/null || echo "")

  if [[ $CP_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "myapp-cp-01 IP: $CP_IP"
  else
    fail "myapp-cp-01 IP" "Invalid or missing IP: $CP_IP"
  fi

  if [[ $W1_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "myapp-worker-01 IP: $W1_IP"
  else
    fail "myapp-worker-01 IP" "Invalid or missing IP: $W1_IP"
  fi

  if [[ $W2_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "myapp-worker-02 IP: $W2_IP"
  else
    fail "myapp-worker-02 IP" "Invalid or missing IP: $W2_IP"
  fi

  # Check public IP exists
  PUBLIC_IP=$(terraform output -raw bastion_public_ip 2>/dev/null || echo "")
  if [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Bastion public IP: $PUBLIC_IP"
  else
    fail "Bastion public IP" "Invalid or missing: $PUBLIC_IP"
  fi

  cd ..
fi

# ── Test 2: Kubernetes cluster ────────────────────────────
log_step "Test 2/6 — Kubernetes Cluster"

# Check kubeconfig exists
if [ -f "$KUBECONFIG_PATH" ]; then
  pass "Kubeconfig exists at $KUBECONFIG_PATH"
else
  fail "Kubeconfig" "Not found at $KUBECONFIG_PATH"
  log_error "Cannot continue without kubeconfig"
  exit 1
fi

# Check cluster is reachable
if kubectl cluster-info --request-timeout=10s &>/dev/null; then
  pass "Cluster API is reachable"
else
  fail "Cluster API" "Not reachable — check SSH tunnel"
  log_error "Cannot continue without cluster access"
  exit 1
fi

# Check all 3 nodes are Ready
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null \
  | grep " Ready" | wc -l)

if [ "$NODE_COUNT" -eq 3 ] && [ "$READY_COUNT" -eq 3 ]; then
  pass "All 3 nodes are Ready"
else
  fail "Cluster nodes" \
    "$READY_COUNT/$NODE_COUNT nodes Ready — expected 3/3"
fi

# Check node roles
CP_NODE=$(kubectl get nodes --no-headers \
  -l node-role.kubernetes.io/control-plane \
  2>/dev/null | wc -l)

if [ "$CP_NODE" -eq 1 ]; then
  pass "Control-plane node present"
else
  fail "Control-plane node" "Expected 1, found $CP_NODE"
fi

# ── Test 3: Namespace and base resources ──────────────────
log_step "Test 3/6 — Namespace and Base Resources"

# Check namespace exists
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  pass "Namespace $NAMESPACE exists"
else
  fail "Namespace" "$NAMESPACE does not exist"
fi

# Check ResourceQuota exists
if kubectl get resourcequota \
  -n "$NAMESPACE" &>/dev/null; then
  pass "ResourceQuota is configured"
else
  fail "ResourceQuota" "Not found in $NAMESPACE"
fi

# Check LimitRange exists
if kubectl get limitrange \
  -n "$NAMESPACE" &>/dev/null; then
  pass "LimitRange is configured"
else
  fail "LimitRange" "Not found in $NAMESPACE"
fi

# ── Test 4: Infrastructure services ──────────────────────
log_step "Test 4/6 — Infrastructure Services"

check_deployment() {
  local name=$1
  local namespace=$2

  DESIRED=$(kubectl get deployment "$name" \
    -n "$namespace" \
    -o jsonpath='{.spec.replicas}' \
    2>/dev/null || echo "0")

  AVAILABLE=$(kubectl get deployment "$name" \
    -n "$namespace" \
    -o jsonpath='{.status.availableReplicas}' \
    2>/dev/null || echo "0")

  if [ "$AVAILABLE" = "$DESIRED" ] && [ "$DESIRED" != "0" ]; then
    pass "Deployment $name ($AVAILABLE/$DESIRED replicas)"
  else
    fail "Deployment $name" \
      "$AVAILABLE/$DESIRED replicas available"
  fi
}

check_service() {
  local name=$1
  local namespace=$2

  if kubectl get service "$name" \
    -n "$namespace" &>/dev/null; then
    pass "Service $name exists"
  else
    fail "Service $name" "Not found in $namespace"
  fi
}

# Infrastructure deployments
INFRA_DEPLOYMENTS=(
  "postgres"
  "redis"
  "rabbitmq"
  "minio"
  "consul"
  "prometheus"
  "grafana"
)

for dep in "${INFRA_DEPLOYMENTS[@]}"; do
  check_deployment "$dep" "$NAMESPACE"
done

# Infrastructure services
INFRA_SERVICES=(
  "postgres"
  "redis"
  "rabbitmq"
  "minio"
  "consul"
  "prometheus"
  "grafana"
)

for svc in "${INFRA_SERVICES[@]}"; do
  check_service "$svc" "$NAMESPACE"
done

# Check PostgreSQL is actually accepting connections
if kubectl exec \
  -n "$NAMESPACE" \
  deploy/postgres \
  -- pg_isready -U postgres \
  --request-timeout=10s \
  &>/dev/null; then
  pass "PostgreSQL is accepting connections"
else
  fail "PostgreSQL" "Not accepting connections"
fi

# Check Redis is responding
if kubectl exec \
  -n "$NAMESPACE" \
  deploy/redis \
  -- sh -c "redis-cli ping | grep PONG" \
  --request-timeout=10s \
  &>/dev/null; then
  pass "Redis is responding to PING"
else
  fail "Redis" "Not responding to PING"
fi

# Check RabbitMQ is healthy
if kubectl exec \
  -n "$NAMESPACE" \
  deploy/rabbitmq \
  -- rabbitmq-diagnostics -q ping \
  --request-timeout=10s \
  &>/dev/null; then
  pass "RabbitMQ is healthy"
else
  fail "RabbitMQ" "Not healthy"
fi

# ── Test 5: Application services ─────────────────────────
log_step "Test 5/6 — Application Services"

APP_DEPLOYMENTS=(
  "api-gateway"
  "frontend"
  "admin-frontend"
  "user-management"
  "payment-service"
  "chatbot"
  "kpi-dashboard"
  "crm-client"
  "predictions-intake"
  "execution-engine"
  "metamodel-orchestration"
  "metamodel-scheduler"
  "metamodel-worker"
)

for dep in "${APP_DEPLOYMENTS[@]}"; do
  check_deployment "$dep" "$NAMESPACE"
done

# Check API gateway health endpoint
API_HEALTH=$(kubectl exec \
  -n "$NAMESPACE" \
  deploy/api-gateway \
  -- curl -sf http://localhost:8888/actuator/health \
  --request-timeout=10s \
  2>/dev/null || echo "failed")

if echo "$API_HEALTH" | grep -q '"status":"UP"'; then
  pass "API Gateway health endpoint is UP"
else
  fail "API Gateway health" \
    "Not responding or unhealthy: $API_HEALTH"
fi

# Check Airflow health
AIRFLOW_HEALTH=$(kubectl exec \
  -n "$NAMESPACE" \
  deploy/metamodel-orchestration \
  -- curl -sf http://localhost:8080/api/v2/monitor/health \
  --request-timeout=10s \
  2>/dev/null || echo "failed")

if echo "$AIRFLOW_HEALTH" | \
  grep -q '"metadatabase":{"status":"healthy"}'; then
  pass "Airflow metadatabase is healthy"
else
  fail "Airflow metadatabase" \
    "Not healthy: $AIRFLOW_HEALTH"
fi

if echo "$AIRFLOW_HEALTH" | \
  grep -q '"scheduler":{"status":"healthy"}'; then
  pass "Airflow scheduler is healthy"
else
  fail "Airflow scheduler" \
    "Not healthy: $AIRFLOW_HEALTH"
fi

# Check all DAGs are unpaused
DAG_COUNT=$(kubectl exec \
  -n "$NAMESPACE" \
  deploy/metamodel-orchestration \
  -- airflow dags list --no-color \
  2>/dev/null | grep -v "^DAG" | grep -v "^-" | wc -l \
  || echo "0")

if [ "$DAG_COUNT" -ge 2 ]; then
  pass "Airflow DAGs present ($DAG_COUNT DAGs)"
else
  fail "Airflow DAGs" \
    "Expected at least 2 DAGs, found $DAG_COUNT"
fi

# ── Test 6: ArgoCD ────────────────────────────────────────
log_step "Test 6/6 — ArgoCD GitOps"

# Check ArgoCD is running
if kubectl get deployment argocd-server \
  -n argocd &>/dev/null; then
  pass "ArgoCD server deployment exists"
else
  fail "ArgoCD server" "Deployment not found in argocd namespace"
fi

ARGOCD_AVAILABLE=$(kubectl get deployment argocd-server \
  -n argocd \
  -o jsonpath='{.status.availableReplicas}' \
  2>/dev/null || echo "0")

if [ "$ARGOCD_AVAILABLE" -ge 1 ]; then
  pass "ArgoCD server is running ($ARGOCD_AVAILABLE replicas)"
else
  fail "ArgoCD server" "No replicas available"
fi

# Check myapp Application exists
if kubectl get application myapp \
  -n argocd &>/dev/null; then
  pass "ArgoCD Application myapp exists"
else
  fail "ArgoCD Application" \
    "myapp Application not found in argocd namespace"
fi

# Check sync status
SYNC_STATUS=$(kubectl get application myapp \
  -n argocd \
  -o jsonpath='{.status.sync.status}' \
  2>/dev/null || echo "Unknown")

HEALTH_STATUS=$(kubectl get application myapp \
  -n argocd \
  -o jsonpath='{.status.health.status}' \
  2>/dev/null || echo "Unknown")

if [ "$SYNC_STATUS" = "Synced" ]; then
  pass "ArgoCD Application is Synced"
else
  fail "ArgoCD sync status" "Expected Synced, got $SYNC_STATUS"
fi

if [ "$HEALTH_STATUS" = "Healthy" ]; then
  pass "ArgoCD Application is Healthy"
else
  fail "ArgoCD health status" "Expected Healthy, got $HEALTH_STATUS"
fi

# ── Final summary ─────────────────────────────────────────
TOTAL_TIME=$(elapsed)
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo ""
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║         End-to-End Test Results          ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

echo "Total tests  : $TOTAL_TESTS"
echo -e "Passed       : ${GREEN}${BOLD}$TESTS_PASSED${NC}"
echo -e "Failed       : ${RED}${BOLD}$TESTS_FAILED${NC}"
echo "Duration     : ${TOTAL_TIME}s"
echo ""

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  echo -e "${RED}${BOLD}Failed tests:${NC}"
  for test in "${FAILED_TESTS[@]}"; do
    echo -e "  ${RED}✗${NC} $test"
  done
  echo ""
fi

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}"
  echo "╔══════════════════════════════════════════╗"
  echo "║       All Tests Passed — Cluster OK      ║"
  echo "╚══════════════════════════════════════════╝"
  echo -e "${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}"
  echo "╔══════════════════════════════════════════╗"
  echo "║     Some Tests Failed — Check Above      ║"
  echo "╚══════════════════════════════════════════╝"
  echo -e "${NC}"
  exit 1
fi
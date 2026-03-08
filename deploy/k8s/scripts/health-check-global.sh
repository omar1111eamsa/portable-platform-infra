#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-myapp}"
ARGO_NS="${ARGO_NS:-argocd}"
APP_NAME="${APP_NAME:-myapp}"
PUBLIC_HOST="${PUBLIC_HOST:-dev.example.com}"
QUEUE_NAME="${QUEUE_NAME:-execution.trade_signals}"

FAILED=0

ok() { echo "[OK]  $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; FAILED=1; }

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1"
    exit 2
  }
}

need kubectl
need awk
need sed
need grep
need curl

echo "== Global Health Check =="
echo "Namespace: $NS"
echo "Argo app:  $ARGO_NS/$APP_NAME"
echo "Host:      $PUBLIC_HOST"
echo

if kubectl version --request-timeout=8s >/dev/null 2>&1; then
  ok "kubectl API reachable"
else
  fail "kubectl API unreachable"
fi

SYNC="$(kubectl -n "$ARGO_NS" get application "$APP_NAME" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
HEALTH="$(kubectl -n "$ARGO_NS" get application "$APP_NAME" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
REV="$(kubectl -n "$ARGO_NS" get application "$APP_NAME" -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)"
if [[ "$SYNC" == "Synced" && "$HEALTH" == "Healthy" ]]; then
  ok "Argo app healthy/synced (rev=${REV:0:7})"
else
  fail "Argo app state is sync=$SYNC health=$HEALTH (rev=${REV:0:7})"
fi

required_deploys=(
  api-gateway
  frontend
  predictions-intake
  metamodel-orchestration
  metamodel-scheduler
  metamodel-dag-processor
  execution-engine
  rabbitmq
  postgres
)

echo
echo "Deployments:"
for d in "${required_deploys[@]}"; do
  if ! kubectl -n "$NS" get deploy "$d" >/dev/null 2>&1; then
    fail "Deployment missing: $d"
    continue
  fi
  ready="$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  desired="$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  img="$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
  ready="${ready:-0}"
  desired="${desired:-0}"
  if [[ "$ready" == "$desired" && "$desired" != "0" ]]; then
    ok "$d ready $ready/$desired ($img)"
  else
    fail "$d ready $ready/$desired ($img)"
  fi
done

echo
echo "Ingress:"
ING="$(kubectl -n "$NS" get ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)"
expected=$'ingress-ip-api\ningress-ip-frontend'
if [[ "$ING" == "$expected" ]]; then
  ok "Ingress exposure limited to ingress-ip-api + ingress-ip-frontend"
else
  fail "Unexpected ingress objects in namespace $NS"
  echo "$ING"
fi

echo
echo "RabbitMQ:"
if kubectl -n "$NS" get deploy rabbitmq >/dev/null 2>&1; then
  qline="$(kubectl -n "$NS" exec deploy/rabbitmq -- rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers 2>/dev/null | awk -v q="$QUEUE_NAME" '$1==q{print $0}')"
  if [[ -n "$qline" ]]; then
    q_ready="$(echo "$qline" | awk '{print $2}')"
    q_unack="$(echo "$qline" | awk '{print $3}')"
    q_cons="$(echo "$qline" | awk '{print $4}')"
    if [[ "${q_cons:-0}" -ge 1 ]]; then
      ok "Queue $QUEUE_NAME consumers=$q_cons ready=$q_ready unacked=$q_unack"
    else
      fail "Queue $QUEUE_NAME has no consumers"
    fi
  else
    fail "Queue $QUEUE_NAME not found"
  fi
else
  fail "rabbitmq deployment not found"
fi

echo
echo "Airflow DAG:"
if kubectl -n "$NS" exec deploy/metamodel-orchestration -- airflow dags list --output plain 2>/dev/null | grep -q '^metapipeline_dag'; then
  ok "metapipeline_dag is parsed"
else
  fail "metapipeline_dag not listed (parse issue)"
fi

echo
echo "Public endpoints:"
code_root="$(curl -k -s -o /dev/null -w '%{http_code}' "https://${PUBLIC_HOST}/")"
if [[ "$code_root" =~ ^(200|301|302|307|308)$ ]]; then
  ok "https://${PUBLIC_HOST}/ -> HTTP $code_root"
else
  fail "https://${PUBLIC_HOST}/ -> HTTP $code_root"
fi

oauth_hdrs="$(curl -k -I -s "https://${PUBLIC_HOST}/api/auth/oauth2/google" || true)"
if echo "$oauth_hdrs" | grep -qi '^HTTP/.* 302'; then
  if echo "$oauth_hdrs" | grep -qi 'location: .*oauth2/authorization/google'; then
    ok "/api/auth/oauth2/google redirects to /oauth2/authorization/google"
  else
    fail "OAuth redirect location is unexpected"
  fi
else
  fail "/api/auth/oauth2/google is not HTTP 302"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "RESULT: HEALTHY"
  exit 0
else
  echo "RESULT: NOT_HEALTHY"
  exit 1
fi

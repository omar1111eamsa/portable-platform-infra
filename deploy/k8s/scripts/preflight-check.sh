#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EXPECTED_FRONTEND_URL="https://dev.example.com"
EXPECTED_REDIRECT_URI="https://dev.example.com/login/oauth2/code/google"

ok() { printf "OK   %s\n" "$1"; }
warn() { printf "WARN %s\n" "$1"; }
fail() { printf "FAIL %s\n" "$1"; FAILED=1; }

FAILED=0

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found in PATH"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found in PATH"
  exit 1
fi

if ! kubectl version --request-timeout=8s >/dev/null 2>&1; then
  echo "kubectl cannot reach cluster (check KUBECONFIG/tunnel)"
  exit 1
fi

if curl -fsS "https://dev.example.com/" >/dev/null 2>&1; then
  ok "TLS trust for https://dev.example.com"
else
  fail "TLS trust for https://dev.example.com (curl verify failed)"
fi

FRONTEND_URL="$(
  kubectl -n myapp get secret google-oauth-credentials \
    -o jsonpath='{.data.FRONTEND_URL}' 2>/dev/null | base64 -d || true
)"
REDIRECT_URI="$(
  kubectl -n myapp get secret google-oauth-credentials \
    -o jsonpath='{.data.GOOGLE_REDIRECT_URI}' 2>/dev/null | base64 -d || true
)"

if [[ "$FRONTEND_URL" == "$EXPECTED_FRONTEND_URL" ]]; then
  ok "google-oauth-credentials FRONTEND_URL=$EXPECTED_FRONTEND_URL"
else
  fail "google-oauth-credentials FRONTEND_URL is '$FRONTEND_URL'"
fi

if [[ "$REDIRECT_URI" == "$EXPECTED_REDIRECT_URI" ]]; then
  ok "google-oauth-credentials GOOGLE_REDIRECT_URI=$EXPECTED_REDIRECT_URI"
else
  fail "google-oauth-credentials GOOGLE_REDIRECT_URI is '$REDIRECT_URI'"
fi

ARGO_SYNC="$(kubectl -n argocd get application myapp -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
ARGO_HEALTH="$(kubectl -n argocd get application myapp -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

if [[ "$ARGO_SYNC" == "Synced" && "$ARGO_HEALTH" == "Healthy" ]]; then
  ok "Argo app myapp is Synced/Healthy"
else
  fail "Argo app myapp is sync='$ARGO_SYNC' health='$ARGO_HEALTH'"
fi

DEPLOY_FAILS="$(
  kubectl -n myapp get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.availableReplicas}{" "}{.status.replicas}{"\n"}{end}' \
  | awk '$2!=$3 {print $1 " available=" $2 " desired=" $3}'
)"

if [[ -z "$DEPLOY_FAILS" ]]; then
  ok "All myapp deployments available"
else
  fail "Deployments not fully available:"
  printf "%s\n" "$DEPLOY_FAILS"
fi

if [[ -n "${PREFLIGHT_SIGNUP_TEST_EMAIL:-}" ]]; then
  SIGNUP_RESP="$(
    curl -k -s -X POST "https://dev.example.com/api/auth/signup/initiate" \
      -H "Content-Type: application/json" \
      --data "{\"email\":\"${PREFLIGHT_SIGNUP_TEST_EMAIL}\"}" || true
  )"
  if echo "$SIGNUP_RESP" | rg -q '"verificationCode"\s*:'; then
    fail "Signup response exposes verificationCode (security issue)"
  else
    ok "Signup response does not expose verificationCode"
  fi
else
  warn "Skipped signup leak check (set PREFLIGHT_SIGNUP_TEST_EMAIL to enable)"
fi

if command -v rg >/dev/null 2>&1; then
  if rg -n --hidden -g '!.git' -g '!**/node_modules/**' -g '!**/.next/**' -g '!**/target/**' -g '!**/build/**' -g '!deploy/k8s/scripts/preflight-check.sh' 'ngrok' "$ROOT_DIR" >/dev/null 2>&1; then
    fail "Found 'ngrok' references in repository"
  else
    ok "No 'ngrok' references in repository files"
  fi
else
  warn "rg not found; skipped repository ngrok scan"
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "Preflight PASS"
  exit 0
fi

echo "Preflight FAIL"
exit 1

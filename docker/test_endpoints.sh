#!/usr/bin/env bash
set -eu

HOST="http://localhost:8080"
EMAIL="alice+test@example.com"
PASSWORD="testpass123"
FULL_NAME="Alice Test"
ROLE="user"
PLAN_TYPE=199
PAYMENT_REF="TEST-PAY-001"

echo
echo "=== CQOS User Management Service end-to-end test ==="
echo

# helper: extract token using jq if available, fallback to grep+sed
extract_token() {
  body="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq -r '.jwt_token // .token // empty'
  else
    # try naive grep/sed
    echo "$body" | sed -n 's/.*"jwt_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  fi
}

# helper: extract user_id
extract_user_id() {
  body="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq -r '.user_id // empty'
  else
    echo "$body" | sed -n 's/.*"user_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  fi
}

# 1) Register user
echo "1) Registering user: $EMAIL"
register_resp="$(curl -s -w "\n%{http_code}" -X POST "$HOST/internal/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"full_name\":\"$FULL_NAME\",\"role\":\"$ROLE\"}" )"

# split body and code
register_body="$(echo "$register_resp" | sed '$d')"
register_code="$(echo "$register_resp" | tail -n1)"

echo "HTTP $register_code"
echo "Response: $register_body"
USER_ID="$(extract_user_id "$register_body")"

if [ "$register_code" = "201" ] && echo "$register_body" | grep -qi '"success":[[:space:]]*true'; then
  echo "-> register ok"
elif [ "$register_code" = "409" ] && echo "$register_body" | grep -qi "already"; then
  echo "-> user already exists (ok for test)"
else
  echo "-> register may have failed (continue to login to check)"
fi
echo

# 2) Login to get JWT
echo "2) Logging in to get JWT"
login_resp="$(curl -s -w "\n%{http_code}" -X POST "$HOST/internal/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" )"

login_body="$(echo "$login_resp" | sed '$d')"
login_code="$(echo "$login_resp" | tail -n1)"

echo "HTTP $login_code"
echo "Response: $login_body"
if [ "$login_code" != "200" ]; then
  echo "ERROR: login failed, cannot continue."
  exit 2
fi

TOKEN="$(extract_token "$login_body")"
if [ -z "$USER_ID" ]; then
  USER_ID="$(extract_user_id "$login_body")"
fi
if [ -z "$TOKEN" ]; then
  echo "ERROR: token not found in login response."
  exit 3
fi
echo "-> Received token (first 64 chars): ${TOKEN:0:64}..."
echo

# 3) Validate token
echo "3) Validating token"
validate_resp="$(curl -s -w "\n%{http_code}" -X POST "$HOST/internal/auth/validate-token" \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN\"}" )"

validate_body="$(echo "$validate_resp" | sed '$d')"
validate_code="$(echo "$validate_resp" | tail -n1)"
echo "HTTP $validate_code"
echo "Response: $validate_body"
if [ "$validate_code" = "200" ] && echo "$validate_body" | grep -qi '"valid":[[:space:]]*true'; then
  echo "-> token valid"
else
  echo "-> token invalid or validation failed"
fi
echo

if [ -n "$USER_ID" ]; then
  echo "4) Fetching permissions snapshot for $USER_ID"
  perms_resp="$(curl -s -w "\n%{http_code}" "$HOST/internal/users/$USER_ID/permissions")"
  perms_body="$(echo "$perms_resp" | sed '$d')"
  perms_code="$(echo "$perms_resp" | tail -n1)"
  echo "HTTP $perms_code"
  echo "Response: $perms_body"
  echo
fi

# 5) Update subscription
echo "5) Updating subscription for $EMAIL (plan $PLAN_TYPE)"
sub_resp="$(curl -s -w "\n%{http_code}" -X PUT "$HOST/internal/users/$(printf "%s" "$EMAIL" | sed 's/@/%40/g')/subscription" \
  -H "Content-Type: application/json" \
  -d "{\"plan_type\": $PLAN_TYPE, \"payment_reference\": \"$PAYMENT_REF\"}" )"

sub_body="$(echo "$sub_resp" | sed '$d')"
sub_code="$(echo "$sub_resp" | tail -n1)"
echo "HTTP $sub_code"
echo "Response: $sub_body"
if [ "$sub_code" = "200" ] || echo "$sub_body" | grep -qi "updated"; then
  echo "-> subscription update OK"
else
  echo "-> subscription update may have failed"
fi
echo

echo "=== Test complete ==="

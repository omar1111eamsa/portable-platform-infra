#!/bin/bash
# Vérifie que le flux OAuth2 Google fonctionne via ngrok
# Usage: ./verify-oauth.sh [NGROK_HOST]
# Exemple: ./verify-oauth.sh example.ngrok-free.dev

set -e

NGROK_HOST="${1:-example.ngrok-free.dev}"
BASE_URL="https://${NGROK_HOST}"
SKIP_HEADER="ngrok-skip-browser-warning: 1"

echo "=== Vérification OAuth2 via $BASE_URL ==="

# 1. /api/auth/oauth2/google → 302 → /oauth2/authorization/google
echo ""
echo "1. GET /api/auth/oauth2/google (initiation)..."
RESP=$(curl -sI -H "$SKIP_HEADER" "$BASE_URL/api/auth/oauth2/google")
STATUS=$(echo "$RESP" | head -1)
LOCATION=$(echo "$RESP" | grep -i "^Location:" | cut -d' ' -f2 | tr -d '\r')

if echo "$STATUS" | grep -q "302"; then
  echo "   OK: 302 Found"
else
  echo "   ERREUR: attendu 302, reçu $STATUS"
  exit 1
fi

if echo "$LOCATION" | grep -q "/oauth2/authorization/google"; then
  echo "   OK: Location = $LOCATION"
else
  echo "   ERREUR: Location incorrecte: $LOCATION (attendu: .../oauth2/authorization/google)"
  exit 1
fi

# 2. /oauth2/authorization/google → 302 → Google
echo ""
echo "2. GET /oauth2/authorization/google (redirect vers Google)..."
RESP2=$(curl -sI -L -H "$SKIP_HEADER" "$BASE_URL/oauth2/authorization/google" 2>/dev/null | head -30)
REDIRECT_TO_GOOGLE=$(echo "$RESP2" | grep -i "^Location:" | grep "accounts.google.com" | head -1)

if [ -n "$REDIRECT_TO_GOOGLE" ]; then
  echo "   OK: Redirection vers Google OAuth détectée"
else
  # Vérifier si on a une redirection vers /auth/login (échec)
  LOGIN_REDIRECT=$(echo "$RESP2" | grep -i "^Location:" | grep "/auth/login" | head -1)
  if [ -n "$LOGIN_REDIRECT" ]; then
    echo "   ERREUR: Redirection vers /auth/login au lieu de Google - OAuth cassé"
    exit 1
  fi
  echo "   ATTENTION: Pas de redirection vers Google visible (vérifier manuellement)"
fi

echo ""
echo "=== OAuth2 OK ===
"
echo "Test complet: ouvrir $BASE_URL/auth/login et cliquer 'Sign in with Google'"

#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-coverage-build}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COVERAGE_ARTIFACT_DIR="$ROOT_DIR/coverage"
mkdir -p "$COVERAGE_ARTIFACT_DIR"

if ! command -v gcovr >/dev/null 2>&1; then
  echo "gcovr not found; attempting to install via pip"
  if ! python3 -m pip install --user gcovr >/dev/null; then
    echo "Failed to install gcovr. Please install it manually (pip install gcovr)." >&2
    exit 1
  fi
fi

export PATH="$HOME/.local/bin:$PATH"

rm -rf "$ROOT_DIR/$BUILD_DIR"
cmake -S "$ROOT_DIR" -B "$ROOT_DIR/$BUILD_DIR" -DENABLE_COVERAGE=ON
cmake --build "$ROOT_DIR/$BUILD_DIR"
(cd "$ROOT_DIR/$BUILD_DIR" && ctest --output-on-failure)

cleanup() {
  set +e
  if [[ -n "${SERVICE_PID:-}" ]]; then
    kill "$SERVICE_PID" >/dev/null 2>&1 || true
    wait "$SERVICE_PID" >/dev/null 2>&1 || true
  fi
  docker compose -f "$ROOT_DIR/docker/docker-compose.yml" down >/dev/null 2>&1 || true
}

trap cleanup EXIT

docker compose -f "$ROOT_DIR/docker/docker-compose.yml" up -d postgres redis >/dev/null

SERVICE_BIN="$ROOT_DIR/$BUILD_DIR/user_management_service"
SERVICE_PORT="${SERVICE_PORT:-8080}"

JWT_PRIVATE_PATH="$ROOT_DIR/keys/private.pem"
JWT_PUBLIC_PATH="$ROOT_DIR/keys/public.pem"

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-cqos}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

GCOV_PREFIX_DIR="$ROOT_DIR/$BUILD_DIR/gcov"
rm -rf "$GCOV_PREFIX_DIR"
mkdir -p "$GCOV_PREFIX_DIR"
export GCOV_PREFIX="$GCOV_PREFIX_DIR"
export GCOV_PREFIX_STRIP=4

RATE_LIMIT_TESTMODE=1 \
JWT_PRIVATE_PATH="$JWT_PRIVATE_PATH" \
JWT_PUBLIC_PATH="$JWT_PUBLIC_PATH" \
DB_HOST="$DB_HOST" \
DB_PORT="$DB_PORT" \
DB_NAME="$DB_NAME" \
DB_USER="$DB_USER" \
DB_PASSWORD="$DB_PASSWORD" \
REDIS_HOST="$REDIS_HOST" \
REDIS_PORT="$REDIS_PORT" \
SERVICE_HOST="0.0.0.0" \
SERVICE_PORT="$SERVICE_PORT" \
"$SERVICE_BIN" &
SERVICE_PID=$!

HEALTH_URL="http://127.0.0.1:$SERVICE_PORT/health"
for _ in {1..60}; do
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
  echo "Service failed to become healthy for coverage run" >&2
  exit 1
fi

SERVICE_BASE_URL="http://127.0.0.1:$SERVICE_PORT" \
REQUEST_TIMEOUT=10 \
python3 "$ROOT_DIR/tests/integration/test_api.py"

kill "$SERVICE_PID"
wait "$SERVICE_PID" >/dev/null 2>&1 || true
unset SERVICE_PID

docker compose -f "$ROOT_DIR/docker/docker-compose.yml" down >/dev/null

rsync -a "$GCOV_PREFIX_DIR/" "$ROOT_DIR/$BUILD_DIR/" >/dev/null

FILTER_REGEX="$ROOT_DIR/src/(auth_manager|bcrypt_utils|logger|metrics|config_loader)\\.cpp"

gcovr \
  --root "$ROOT_DIR" \
  --filter "$FILTER_REGEX" \
  --exclude "third_party" \
  --xml "$COVERAGE_ARTIFACT_DIR/coverage.xml" \
  --html-details "$COVERAGE_ARTIFACT_DIR/coverage.html" \
  --html-theme github.green \
  --txt "$COVERAGE_ARTIFACT_DIR/coverage.txt" \
  --json "$COVERAGE_ARTIFACT_DIR/coverage.json" \
  --merge-mode-functions merge-use-line-0 \
  --fail-under-line 80

echo "Coverage summary:" 
cat "$COVERAGE_ARTIFACT_DIR/coverage.txt"

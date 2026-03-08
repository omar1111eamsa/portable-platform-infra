#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-myapp}"
PG_DEPLOY="${PG_DEPLOY:-postgres}"
AIRFLOW_DEPLOY="${AIRFLOW_DEPLOY:-metamodel-orchestration}"
CLEANUP="${CLEANUP:-false}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }
need kubectl
need awk
need sed

TEST_CYCLE_ID="${TEST_CYCLE_ID:-$(cat /proc/sys/kernel/random/uuid)}"
TEST_PRED_ID="${TEST_PRED_ID:-$(cat /proc/sys/kernel/random/uuid)}"
TEST_USER_ID="${TEST_USER_ID:-$(cat /proc/sys/kernel/random/uuid)}"

echo "[1/6] Inserting test prediction..."
kubectl exec -n "$NS" deploy/"$PG_DEPLOY" -- psql -U postgres -d prediction_db -v ON_ERROR_STOP=1 -c "
INSERT INTO predictions_raw (
  id,
  asset,
  coefficient_multiplier,
  cycle_id,
  horizon,
  ingested_at,
  predicted_move_percent,
  prediction_action,
  price,
  user_confidence,
  user_id
) VALUES (
  '${TEST_PRED_ID}',
  'BTCUSDT',
  1.0,
  '${TEST_CYCLE_ID}',
  '1h',
  NOW(),
  2.5,
  'BUY',
  65000.0,
  0.92,
  '${TEST_USER_ID}'
);"

echo "[2/6] Triggering metapipeline_dag..."
kubectl exec -n "$NS" deploy/"$AIRFLOW_DEPLOY" -- airflow dags trigger metapipeline_dag >/dev/null
sleep 2

RUN_ID="$(kubectl exec -n "$NS" deploy/"$AIRFLOW_DEPLOY" -- airflow dags list-runs metapipeline_dag --no-backfill \
  | awk '/manual__/ {print $3; exit}' | tr -d '[:space:]')"

if [[ -z "${RUN_ID}" ]]; then
  echo "Unable to detect DAG run id"
  exit 1
fi

echo "Detected RUN_ID=${RUN_ID}"

echo "[3/6] Waiting for DAG run completion (max 12 min)..."
for i in $(seq 1 72); do
  STATE_LINE="$(kubectl exec -n "$NS" deploy/"$AIRFLOW_DEPLOY" -- airflow dags list-runs metapipeline_dag --no-backfill | grep "${RUN_ID}" || true)"
  if [[ "$STATE_LINE" == *" success "* ]]; then
    echo "DAG run succeeded"
    break
  fi
  if [[ "$STATE_LINE" == *" failed "* ]]; then
    echo "DAG run failed"
    kubectl exec -n "$NS" deploy/"$AIRFLOW_DEPLOY" -- airflow tasks states-for-dag-run metapipeline_dag "$RUN_ID" || true
    exit 1
  fi
  sleep 10
  if [[ "$i" -eq 72 ]]; then
    echo "Timeout waiting DAG completion"
    kubectl exec -n "$NS" deploy/"$AIRFLOW_DEPLOY" -- airflow tasks states-for-dag-run metapipeline_dag "$RUN_ID" || true
    exit 1
  fi
done

echo "[4/6] Verifying SQL outputs..."
score_cnt="$(kubectl exec -n "$NS" deploy/"$PG_DEPLOY" -- psql -U postgres -d prediction_db -Atc "SELECT COUNT(*) FROM scored_predictions WHERE cycle_id='${TEST_CYCLE_ID}';")"
signal_cnt="$(kubectl exec -n "$NS" deploy/"$PG_DEPLOY" -- psql -U postgres -d prediction_db -Atc "SELECT COUNT(*) FROM trade_signals WHERE cycle_id='${TEST_CYCLE_ID}';")"
# filled_trades has no cycle_id column in current schema. Link by signal_id from trade_signals.
fill_cnt="$(kubectl exec -n "$NS" deploy/"$PG_DEPLOY" -- psql -U postgres -d prediction_db -Atc "SELECT COUNT(*) FROM filled_trades WHERE signal_id IN (SELECT signal_id FROM trade_signals WHERE cycle_id='${TEST_CYCLE_ID}');")"
reward_cnt="$(kubectl exec -n "$NS" deploy/"$PG_DEPLOY" -- psql -U postgres -d prediction_db -Atc "SELECT COUNT(*) FROM user_rewards WHERE cycle_id='${TEST_CYCLE_ID}';")"

echo "scored_predictions=${score_cnt}"
echo "trade_signals=${signal_cnt}"
echo "filled_trades=${fill_cnt}"
echo "user_rewards=${reward_cnt}"

if [[ "${score_cnt}" -lt 1 || "${signal_cnt}" -lt 1 || "${fill_cnt}" -lt 1 ]]; then
  echo "Pipeline output incomplete for cycle ${TEST_CYCLE_ID} (score/signal/fill)"
  exit 1
fi

if [[ "${reward_cnt}" -lt 1 ]]; then
  echo "WARN: user_rewards=0 for cycle ${TEST_CYCLE_ID} (expected if closed_trades_pnl is not produced yet)"
fi

echo "[5/6] Task states"
kubectl exec -n "$NS" deploy/"$AIRFLOW_DEPLOY" -- airflow tasks states-for-dag-run metapipeline_dag "$RUN_ID"

echo "[6/6] Success"
echo "TEST_CYCLE_ID=${TEST_CYCLE_ID}"
echo "RUN_ID=${RUN_ID}"

if [[ "$CLEANUP" == "true" ]]; then
  echo "Cleanup enabled: deleting test data"
  kubectl exec -n "$NS" deploy/"$PG_DEPLOY" -- psql -U postgres -d prediction_db -v ON_ERROR_STOP=1 -c "
  DELETE FROM user_rewards WHERE cycle_id='${TEST_CYCLE_ID}';
  DELETE FROM filled_trades WHERE signal_id IN (SELECT signal_id FROM trade_signals WHERE cycle_id='${TEST_CYCLE_ID}');
  DELETE FROM trade_signals WHERE cycle_id='${TEST_CYCLE_ID}';
  DELETE FROM scored_predictions WHERE cycle_id='${TEST_CYCLE_ID}';
  DELETE FROM predictions_raw WHERE cycle_id='${TEST_CYCLE_ID}';"
fi

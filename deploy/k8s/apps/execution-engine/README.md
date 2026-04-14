# Execution Engine

## Overview

The execution engine is a realtime RabbitMQ consumer that processes trade signals and records fills. It runs as a Kubernetes Deployment (always-on, not a CronJob) on `backend2`.

## Behaviour

- Subscribes to the `execution.events` exchange and the `trade_signal.created` routing key
- On each message, simulates or forwards the order and writes the result to `filled_trades`
- Accepts both legacy payload format (`orders[].orderId`) and the current format (`signal_id`)
- Connects to PostgreSQL using the `DB_CONN` or `MYAPP_DB_URL` environment variable

## Configuration

| Environment Variable | Description |
|---|---|
| `DB_CONN` | PostgreSQL connection string (primary) |
| `MYAPP_DB_URL` | PostgreSQL connection string (fallback) |
| `RABBITMQ_HOST` | RabbitMQ hostname (default: `rabbitmq`) |
| `RABBITMQ_USERNAME` | RabbitMQ username (default: `guest`) |
| `RABBITMQ_PASSWORD` | RabbitMQ password (default: `guest`) |

## Logs

```bash
kubectl -n myapp logs deploy/execution-engine --tail=50 -f
```

## Verify Connectivity

```bash
# Check filled_trades is being written
kubectl exec -n myapp deploy/postgres -- \
  psql -U postgres -d prediction_db -c "SELECT COUNT(*) FROM filled_trades;"
```

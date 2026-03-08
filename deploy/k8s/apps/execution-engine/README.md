# Execution Engine (Realtime Consumer)

This workload runs `Metamodel-execution-engine` as a realtime RabbitMQ consumer.

- Runtime mode (current): `python consumer_realtime.py`
- Trigger mode: event-driven (`trade_signal.created`)
- Image currently pinned to: `ghcr.io/myapp/cq-execution-engine:4960759`

## Why Deployment (not CronJob)

Execution must consume events continuously from RabbitMQ.
CronJob/batch would introduce latency and miss realtime requirements.

## RabbitMQ flow

- Producer: metamodel portfolio stage publishes to exchange `execution.events`
- Routing key: `trade_signal.created`
- Queue consumed by execution-engine: `execution.trade_signals`

## Check logs/status

`kubectl -n myapp get deploy execution-engine`

`kubectl -n myapp logs deploy/execution-engine`

## Common pull issue (GHCR)

If pod fails with `401 Unauthorized` or `403 Forbidden`, recreate `ghcr-secret`
with a PAT that has `read:packages` (and org SSO authorization if required).

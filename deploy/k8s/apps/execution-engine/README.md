# Execution Engine (Realtime Consumer)

This workload runs `Metamodel-execution-engine` as a realtime RabbitMQ consumer.

- Runtime mode (current): `python consumer_realtime.py`
- Trigger mode: event-driven (`trade_signal.created`)
- Scheduled on node: `backend2` (`nodeSelector`)
- Image pinned in manifest `deployment.yaml` (tag updated by CI)

## Why Deployment (not CronJob)

Execution must consume events continuously from RabbitMQ.
CronJob/batch would introduce latency and miss realtime requirements.

## RabbitMQ flow

- Producer: metamodel portfolio stage publishes to exchange `execution.events`
- Routing key: `trade_signal.created`
- Queue consumed by execution-engine: `execution.trade_signals`

Payload compatibility currently handled by the consumer:
- modern shape with top-level `signal_id`
- legacy shape with `orders[0].orderId`

This keeps the live metamodel publisher and execution-engine aligned during the current dev phase.

## Check logs/status

`kubectl -n myapp get deploy execution-engine`

`kubectl -n myapp logs deploy/execution-engine`

## Common pull issue (GHCR)

If pod fails with `401 Unauthorized` or `403 Forbidden`, recreate `ghcr-secret`
with a PAT that has `read:packages` (and org SSO authorization if required).

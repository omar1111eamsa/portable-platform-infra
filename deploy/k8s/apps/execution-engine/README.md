# Execution Engine (CronJob)

This workload runs `Metamodel-execution-engine` as a batch job.

- Runtime mode (current): `python main.py validate examples/orders/open_limit.sample.json`
- Default trading mode env: `paper`
- Default state: suspended (`spec.suspend: true`)
- Image currently pinned to: `ghcr.io/myapp/cq-execution-engine:0af1fbe`

## Why CronJob (not Deployment)

`execute.py` is a one-shot process. After one cycle it exits.
Using a Deployment would produce restart loops.

## Enable it

1. Create broker secret (if needed):
   `kubectl apply -f deploy/k8s/apps/execution-engine/secret.yaml.example`
2. Unsuspend:
   `kubectl -n myapp patch cronjob execution-engine -p '{"spec":{"suspend":false}}'`

## Run once on demand

`kubectl -n myapp create job --from=cronjob/execution-engine execution-engine-manual-$(date +%s)`

## Check logs

`kubectl -n myapp get jobs | grep execution-engine`

`kubectl -n myapp logs job/<job-name>`

## Common pull issue (GHCR)

If pod fails with `401 Unauthorized` or `403 Forbidden`, recreate `ghcr-secret`
with a PAT that has `read:packages` (and org SSO authorization if required).

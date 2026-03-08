# Execution Engine (CronJob)

This workload runs `Metamodel-execution-engine` as a batch job.

- Source portfolio mode: `trade_signals` from `prediction_db`
- Default trading mode: `paper`
- Default state: suspended (`spec.suspend: true`)

## Why CronJob (not Deployment)

`execute.py` is a one-shot process. After one cycle it exits.
Using a Deployment would produce restart loops.

## Enable it

1. Set broker config in `configmap.yaml` (enable desired broker).
2. Create broker secret (if needed):
   `kubectl apply -f deploy/k8s/apps/execution-engine/secret.yaml.example`
3. Unsuspend:
   `kubectl -n myapp patch cronjob execution-engine -p '{"spec":{"suspend":false}}'`

## Run once on demand

`kubectl -n myapp create job --from=cronjob/execution-engine execution-engine-manual-$(date +%s)`

## Check logs

`kubectl -n myapp get jobs | grep execution-engine`

`kubectl -n myapp logs job/<job-name>`

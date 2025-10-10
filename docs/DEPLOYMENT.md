# Deployment Guide

## Environment Variables
- `SERVICE_HOST` (default `0.0.0.0`)
- `SERVICE_PORT` (default `8080`)
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `REDIS_HOST`, `REDIS_PORT`
- `JWT_PRIVATE_PATH`, `JWT_PUBLIC_PATH`
- `RATE_LIMIT_TESTMODE` (optional)
- `CONFIG_PATH` (optional JSON file; see below)

> **Note:** The Docker image generates its own RSA keypair under `/usr/local/bin/keys`. When running the service outside of Docker, ensure `JWT_*_PATH` points to valid PEM files (sample keys are available under `keys/` or create new ones via `openssl genrsa` / `openssl rsa -pubout`).

## Configuration File
- Copy `config/service_config.example.json` to `config/service_config.json` and adjust values for your environment.
- Set `CONFIG_PATH` to point at the file if it lives outside the default location.
- Environment variables override matching keys in the JSON file, keeping backwards compatibility with existing deployments.

## Docker
- Build images: `make docker-build`
- Run stack: `make docker-run`
- Unit tests: `make docker-test`
- Integration tests: `make docker-integration`

## Migrations
1. `psql -h <host> -U <user> -d <db> -f migrations/001_initialize_schema.sql`
2. Optional seed: `psql -f migrations/002_seed_reference_data.sql`

## Logs & Monitoring
- Structured logs emitted via `logger.hpp` in JSON format.
- Sensitive fields (passwords, tokens) are automatically masked.
- Performance smoke test: `scripts/perf_smoke.sh` (requires python3).

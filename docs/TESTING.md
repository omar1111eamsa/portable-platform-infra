# Testing & Quality Gates

## Unit Tests
- Build: `cmake --build build`
- Run: `ctest --output-on-failure`
- Docker: `make docker-test`

## Integration Tests
- Compose stack: `make docker-run`
- HTTP flow: `make docker-integration`

## Performance Smoke Test
- Ensure the stack is running (`make docker-run`).
- Execute `scripts/perf_smoke.sh` (configure `CONCURRENCY`, `REQUESTS`, `SERVICE_URL`).

## Notes
- Integration tests live in `tests/integration/test_api.py` and exercise `/internal/auth/*` plus the permissions endpoint.
- Unit tests cover hashing, JWT handling, controller edge-cases, subscription logic, and logging.
- Artifacts such as migrations live in `migrations/` and should be applied before running integration tests against a fresh database.

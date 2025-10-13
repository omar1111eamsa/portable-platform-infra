# Testing & Quality Gates

## Unit Tests
- Build: `cmake --build build`
- Run: `ctest --output-on-failure`
- Docker: `make docker-test`

## Integration Tests
- Compose stack: `make docker-run`
- HTTP flow: `make docker-integration`

## Performance Smoke Test

### Requirements
The smoke test validates that the service meets the **production performance requirements**:
- **P95 Latency**: ≤ 50ms
- **Throughput**: ≥ 1000 rps

### Testing Modes

#### 1. Production Mode (Recommended)
- **Purpose**: Validate real-world performance requirements
- **Command**: `make docker-run` (normal operation)
- **Test**: `PERF_VERBOSE=0 CONCURRENCY=220 REQUESTS=5500 ./scripts/perf_smoke.sh`
- **Note**: This tests the service in normal production mode with all optimizations active

#### 2. Performance Testing Mode (Development)
- **Purpose**: Relax rate limits for intensive testing
- **Command**: `make docker-run-perf` (sets `PERF_TEST=1` inside containers)
- **Test**: `./scripts/optimized_validate_token_test.sh`
- **Note**: This mode bypasses some processing for maximum performance measurement

### Configuration
- By default the script enforces the cahier targets (P95 ≤ 50 ms, throughput ≥ 1000 rps)
- Set `P95_TARGET_MS` / `THROUGHPUT_TARGET_RPS` to override or disable (`=0`) when you only need a lighter sanity check
- Use `PERF_VERBOSE=0` for quiet output; `PERF_THROTTLE_SLEEP` can pace requests if you need to avoid hammering shared environments

## Notes
- Integration tests live in `tests/integration/test_api.py` and exercise `/internal/auth/*` plus the permissions endpoint.
- Unit tests cover hashing, JWT handling, controller edge-cases, subscription logic, and logging.
- Artifacts such as migrations live in `migrations/` and should be applied before running integration tests against a fresh database.
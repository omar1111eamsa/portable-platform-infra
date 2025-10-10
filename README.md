# CQOS User Management & Subscription Service

This repository houses the identity microservice that powers MYAPP’s internal authentication, authorization, and subscription enforcement. The implementation follows the “User Management & Subscription Service” cahier des charges and adds observability/automation layers that make the service production-ready.

---

## 1. Architecture & Component Map

| Layer | Responsibility | Key Files |
|-------|----------------|-----------|
| **HTTP API** | Exposes internal REST endpoints (`/internal/auth/*`, `/internal/users/*`) using [`cpp-httplib`](https://github.com/yhirose/cpp-httplib). | `src/user_service_api.cpp`, `include/user_service_api.hpp` |
| **Domain Managers** | Encapsulate core business logic and database interactions for users, subscriptions, and authentication. | `UserController`, `SubscriptionManager`, `AuthManager` |
| **Infrastructure** | Database bootstrap (`Database`), rate limiter (Redis with in-memory fallback), structured logger, migrations, Docker setup. | `src/db.cpp`, `src/ratelimiter*.cpp`, `src/logger.cpp`, `docker/`, `migrations/` |
| **Testing** | Unit test harness (custom), integration tests via Python/requests, perf smoke script. | `tests/`, `tests/integration/`, `scripts/perf_smoke.sh` |

Dependency flow: `main.cpp` wires infrastructure → domain managers → `UserServiceAPI`. External services include PostgreSQL (persistence) and Redis (rate limiting). JWT signing uses RSA keys mounted via Docker.

---

## 2. Database Schema & Migrations

Schema definition lives in `migrations/001_initialize_schema.sql` and mirrors the runtime bootstrap in `Database::initializeSchema()`:

### 2.1 `users`
| Column | Type | Notes |
|--------|------|-------|
| `user_id` | UUID PK | Generated via `gen_random_uuid()` |
| `email` | `VARCHAR(255)` | Unique, indexed |
| `password_hash` | `TEXT` | Stores bcrypt hash (Argon2/plaintext migrated on login) |
| `role` | `VARCHAR(20)` | Enum: `user`, `admin`, `support`, `marketing` |
| `is_active` | `BOOLEAN` | Login blocked if false |
| `full_name` | `VARCHAR(255)` | Optional metadata |
| `created_at`, `updated_at` | `TIMESTAMPTZ` | Auto timestamps |

### 2.2 `subscriptions`
| Column | Type | Notes |
|--------|------|-------|
| `subscription_id` | UUID PK |
| `user_id` | UUID FK (unique) | One active subscription per user |
| `plan_name` | `VARCHAR(50)` | Enum: `FREE`, `PRO`, `ELITE` |
| `status` | `VARCHAR(50)` | Enum: `active`, `past_due`, `canceled` |
| `backtests_per_day_limit` | `INT` | Plan-specific |
| `api_requests_per_hour_limit` | `INT NULL` | `NULL` for entry tier |
| `backtests_used_today` | `INT` | Updated atomically when `/internal/auth/validate-token` is called |
| `quota_reset_at` | `TIMESTAMPTZ` | Next reset timestamp |
| `start_date`, `end_date` | `TIMESTAMPTZ` | Subscription life-cycle |
| `provider_subscription_id` | `TEXT` | External provider reference |
| `updated_at` | `TIMESTAMPTZ` |

### 2.3 `usage_logs`
Captures per-request audit metadata (user id, endpoint, structured metadata) for register/login/validate/permissions flows.

### Migrations
* `001_initialize_schema.sql` – creates all tables, indexes, deduplicates existing rows.
* `002_seed_reference_data.sql` – optional seed users (`admin`, `support`) plus matching subscriptions.

---

## 3. Security & Identity Features

### 3.1 Password Handling
- Registration hashes passwords with bcrypt using `bcrypt_utils::{hashPassword,verifyPassword}` (cost clamps to 10–31).
- Legacy support:
  - Argon2 hashes (from previous libsodium usage) are validated and re-minted as bcrypt on login.
  - Plaintext rows (if any) trigger immediate bcrypt migration on successful login.
- Unit tests cover all pathways (`tests/test_user_controller_edgecases.cpp`, `tests/test_bcrypt_utils.cpp`).

### 3.2 JWT Issuance & Validation
- `AuthManager` loads RSA key pair (`keys/private.pem`, `keys/public.pem`).
- Tokens embed `sub` (user_id), `role`, and `plan` claims; default TTL = 3600 seconds.
- Validation enforces issuer and signature, returning structured errors on expired/tampered tokens.
- Integration tests simulate register → login → validate flows to confirm claims.
- Docker images generate a fresh RSA keypair during build (`/usr/local/bin/keys`); when running natively, reuse `keys/` or generate equivalent PEM files with `openssl`.

- Redis-backed limiter (`src/ratelimiter.cpp`) keys by user/plan with per-minute and per-day caps (configurable via env or test mode).
- In-memory fallback (`src/ratelimiter_global.cpp`) ensures binaries still run without Redis (used for unit tests).
- API endpoints log 429 responses and propagate reason codes.
- During local perf testing you can temporarily relax throttling via Docker Compose env vars (e.g., `RATE_LIMIT_PRO_PER_MIN`, `RATE_LIMIT_PRO_PER_DAY`).

### 3.4 Structured Logging
- Centralized `log_event(LogLevel, message, fields)` function outputs JSON with ISO timestamps and masked sensitive fields (`password`, `token`, etc.).
- Instrumented in `main.cpp` (startup events) and `user_service_api.cpp` (register/login/validate/subscription flows).
- Tests ensure PII masking works (`tests/test_logger.cpp`).

---

## 4. Endpoint Walkthrough

### 4.1 `POST /internal/auth/register`
1. Rate-limited on client IP.
2. Validates payload (`email`, `password`, optional `full_name`, `role`).
3. Creates bcrypt hash; aborts with 409 if email exists.
4. Initializes subscription to plan code `0` (FREE) via `SubscriptionManager`.
5. Logs structured event with anonymized email and generated `user_id`.

### 4.2 `POST /internal/auth/login`
1. Rate-limited on email.
2. Validates credentials, migrating legacy hashes transparently.
3. Pulls latest subscription plan (`normalizePlan` handles numeric→name mapping).
4. Issues JWT with `user_id`, `role`, `plan`.
5. Responds with plan info to let clients adjust allowances.

### 4.3 `POST /internal/auth/validate-token`
1. Checks JWT signature & expiry.
2. Loads joined user/subscription snapshot.
3. Applies rate limiting keyed to user/plan.
4. Returns full permission payload (flags, quotas, plan metadata).
5. Logs success/failure for observability.

### 4.4 `GET /internal/users/{id}/permissions`
Returns identical payload to `/validate-token` without needing JWT (for internal orchestrators). 404 if user missing; logs both success and not-found cases.

### 4.5 `PUT /internal/users/{email}/subscription`
Operational endpoint used by billing to set plan code (`0`, `89`, `199` → `FREE/PRO/ELITE`). Upserts `subscriptions`, recalculates plan quotas, and logs outcome.

---

## 5. Test Strategy

### 5.1 Unit Tests (`tests/`)
Custom harness `tests/test_framework.hpp` registered via macros (`TEST_CASE`). Notable suites:
- `test_auth_manager_*.cpp` – token roundtrip, expiry, tampering.
- `test_bcrypt_utils.cpp` – hashing verification and cost clamp.
- `test_user_controller*.cpp` – duplicate registration, inactive user handling, migration from plaintext/Argon2, wrong password failure.
- `test_subscription_manager.cpp` – plan mapping, API quota handling, failure scenarios.
- `test_logger.cpp` – structured logging, sensitive field masking.

Run locally: `cmake --build build && ctest --output-on-failure`  
Dockerized runner: `make docker-test`

### 5.2 Integration Tests (`tests/integration/test_api.py`)
- Python/requests script launched via compose service `integration_tests`.
- Waits for `/health`, executes register → subscription upgrade → login → validate → GET permissions.
- Confirms response payloads, plan transitions, and readiness of the entire stack (Postgres, Redis, service).

Run: `make docker-integration`

### 5.3 Performance Smoke (`scripts/perf_smoke.sh`)
- Registers a temporary user, upgrades to PRO, acquires a JWT, and fires configurable concurrent `/validate-token` calls.
- Summarizes request count, errors, elapsed seconds, P50/P95 latency (ms).
- Used by CI to ensure regressions are caught early (not a full load test).
- Rate-limit thresholds can be relaxed via compose env vars (e.g., `RATE_LIMIT_PRO_PER_MIN`, `RATE_LIMIT_PRO_PER_DAY`) so Redis doesn’t throttle smoke runs.
- Under the hood the service uses pooled PostgreSQL connections plus a short-lived snapshot cache in `/internal/auth/validate-token` to keep the hot path under 50 ms P95.

Example: `REQUEST_TIMEOUT=30 CONCURRENCY=5 REQUESTS=100 scripts/perf_smoke.sh`

---

## 6. Performance & Operational Optimizations

- **Database connection pooling & self-healing schema upgrades.** `Database` warms eight PostgreSQL connections on startup, grows the pool on demand, and reuses them across requests so `/validate-token` does not pay the TCP setup cost. The bootstrap routine also renames legacy `id` columns, deduplicates historical `subscriptions`, and enforces indexes/constraints so the hot queries stay on optimized plans without manual migration steps.
- **5 s snapshot cache for permission lookups.** `UserServiceAPI` caches joined user/subscription rows in memory (`fetchUserSnapshotById`) for five seconds. This avoids repetitive joins on back-to-back auth checks while keeping data fresh; cache entries are flushed immediately after subscription updates so the `/validate-token` path still reflects new quotas.
- **Adaptive rate limiting with graceful degradation.** The Redis-backed `RateLimiter` honors per-plan env overrides (`RATE_LIMIT_<PLAN>_PER_MIN/DAY`) and a `RATE_LIMIT_TESTMODE` toggle that shrinks ceilings for CI. If Redis goes away, requests fail-open with a `redis_unavailable` reason so operations retain control. A deterministic in-memory fallback (`ratelimiter_global.cpp`) is compiled in for unit tests and developer machines that do not have Redis.
- **Usage audit trail & quota enforcement.** Each authentication and subscription endpoint records structured rows in `usage_logs`, while `/internal/auth/validate-token` atomically increments `backtests_used_today` and surfaces `quota_exhausted` responses once plan limits are hit.
- **Secure logging pipeline.** `log_event` emits JSON lines with ISO8601 timestamps and automatically masks sensitive fields (`password`, `token`, etc.), satisfying the spec’s “logs structurés et métriques” requirement and keeping PII out of aggregated logs.
- **Docker build tuned for production parity.** The multi-stage `docker/Dockerfile` installs toolchains only in the builder stage, copies the compiled binaries plus libpqxx into a minimal runtime image, and generates RSA keys during the image build so containers are ready-to-run in CI/CD without extra scripts.
- **Latency guardrail automation.** `scripts/perf_smoke.sh` provisions a user, upgrades to PRO, and hammers `/internal/auth/validate-token` with configurable concurrency. The script prints P50/P95 metrics, giving a repeatable check that the connection pool, cache, and rate limiter tuning hold the endpoint under the 50 ms P95 objective.

## 7. Tooling & Automation

### 7.1 Make Targets (`user_management_service/Makefile`)
| Target | Description |
|--------|-------------|
| `make build` | Configure & compile with CMake |
| `make run` | Build + run native binary |
| `make docker-build` | Build Docker images for service & tests |
| `make docker-run` | Launch compose stack (`postgres`, `redis`, `user_service`) |
| `make docker-test` | Execute unit tests inside `user_service_tests` container |
| `make docker-integration` | Start stack, run integration tests, auto teardown |
| `make perf-smoke` | Execute local smoke test script |
| `REQUEST_TIMEOUT=30 CONCURRENCY=5 REQUESTS=100 ./scripts/perf_smoke.sh` | Example perf run against `/internal/auth/validate-token` |

### 7.2 Docker Compose (`docker/docker-compose.yml`)
- **postgres** (14), **redis** (7), **user_service** (built from repo), **user_service_tests**, **integration_tests**.
- Keys mounted read-only to service container.
- Compose is used both for local dev and CI stages.

### 7.3 Configuration
- Default runtime settings live in `config/service_config.example.json`; copy it to `config/service_config.json` (or point `CONFIG_PATH` elsewhere) and tweak hostnames, credentials, and rate limits.
- Environment variables still override file values, so existing deployment scripts continue to work.
- Set `CONFIG_PATH=/path/to/config.json` to load a custom configuration outside the repo.

### 7.4 CI Pipeline (`.github/workflows/ci.yml`)
Steps:
1. Checkout & install toolchain (cmake, libpqxx, libsodium, hiredis, python3, docker).
2. Configure & build C++ sources.
3. Run unit tests via `ctest`.
4. Build Docker images and run containerized unit tests.
5. Spin stack, execute integration tests, and tear down.
6. Launch perf smoke script against running stack.

---

## 8. Remaining Specification Gaps

Despite the progress, several cahier requirements remain:
1. **Metrics & load tests:** While structured logs and smoke tests exist, the spec mandates “Monitoring: logs structurés et métriques exposées” and proven throughput (≥1000 req/s) with P95 < 50 ms. Needs:
   - Metrics exporter (e.g., Prometheus counters/histograms) or StatsD integration.
   - Automated load/perf job validating SLOs (Locust/k6/JMeter).
2. **Coverage reporting:** Tests target breadth but there is no coverage tooling/report to demonstrate ≥80 % coverage (gcov/lcov or llvm-cov recommended).
3. **HTTP framework alignment:** Specification called for Crow/Boost.Beast; document the deviation or migrate the HTTP layer accordingly.

Tracking for these items lives in `docs/TODO.md`.

---

## 9. Getting Started Quickly

1. **Clone & configure**
   ```bash
   git clone <repo>
   cd user_management_service
   cmake -S . -B build
   cmake --build build
   ```
2. **Run locally (native)**
   ```bash
   ./build/user_management_service \
     SERVICE_HOST=0.0.0.0 SERVICE_PORT=8080 \
     DB_HOST=localhost DB_PORT=5432 DB_USER=user DB_PASSWORD=pass \
     JWT_PRIVATE_PATH=keys/private.pem JWT_PUBLIC_PATH=keys/public.pem
   ```
3. **Docker workflow**
   ```bash
   make docker-build
   make docker-run
   ```
   Service available on `http://localhost:8080`.

4. **Verify via tests**
   ```bash
   make docker-test          # Unit tests
   make docker-integration   # End-to-end flow
   scripts/perf_smoke.sh     # Latency spot-check
   ```

---

## 10. Reference Materials

- 📄 Specification: `user_management_service/user_management_and_subscription_service_update (2).pdf`
- 📚 Testing Guide: `docs/TESTING.md`
- 🚀 Deployment Guide: `docs/DEPLOYMENT.md`
- ✅ Outstanding tasks: `docs/TODO.md`

This README should provide all context needed to maintain, extend, and validate the service. Please keep it up-to-date as future features (usage logging, metrics, quotas, coverage) are delivered.

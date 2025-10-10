#!/usr/bin/env bash
set -euo pipefail

SERVICE_URL="${SERVICE_URL:-http://localhost:8080}"
CONCURRENCY="${CONCURRENCY:-5}"
REQUESTS="${REQUESTS:-50}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-5}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

python3 - "$SERVICE_URL" "$CONCURRENCY" "$REQUESTS" <<'PY'
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid

service_url, concurrency, total_requests = sys.argv[1:]
concurrency = int(concurrency)
total_requests = int(total_requests)

request_timeout = float(os.environ.get("REQUEST_TIMEOUT", "5"))
health_timeout = float(os.environ.get("HEALTH_TIMEOUT", "60"))

register_url = f"{service_url}/internal/auth/register"
login_url = f"{service_url}/internal/auth/login"
validate_url = f"{service_url}/internal/auth/validate-token"
update_url_template = f"{service_url}/internal/users/{{}}/subscription"
health_url = f"{service_url}/health"


def wait_for_health():
    deadline = time.time() + health_timeout
    while time.time() < deadline:
        try:
            req = urllib.request.Request(health_url)
            with urllib.request.urlopen(req, timeout=request_timeout) as resp:
                if resp.status == 200:
                    return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("Service did not become healthy within the allotted time")


def json_request(url, payload, method="POST"):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method=method)
    return urllib.request.urlopen(req, timeout=request_timeout)


def main():
    wait_for_health()

    unique = uuid.uuid4().hex
    email = f"perf-{unique}@example.com"
    password = "PerfSmoke123!"

    # Register user
    with json_request(register_url, {
        "email": email,
        "password": password,
        "full_name": "Perf Smoke",
        "role": "user"
    }):
        pass

    # Upgrade subscription to PRO
    with json_request(update_url_template.format(email), {
        "plan_type": 89,
        "payment_reference": f"PERF-{unique}"
    }, method="PUT"):
        pass

    # Login to get JWT token
    with json_request(login_url, {
        "email": email,
        "password": password
    }) as resp:
        login_body = json.load(resp)
        token = login_body["token"]

    payload = json.dumps({"token": token}).encode()
    headers = {"Content-Type": "application/json"}

    latencies = []
    state = {"count": 0}
    errors = {"total": 0}
    lock = threading.Lock()

    start = time.perf_counter()

    def worker():
        while True:
            with lock:
                if state["count"] >= total_requests:
                    return
                state["count"] += 1
            begin = time.perf_counter()
            req = urllib.request.Request(validate_url, data=payload, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=request_timeout) as resp:
                    if resp.status != 200:
                        with lock:
                            if errors["total"] == 0:
                                print(f"debug_error: HTTP {resp.status} {resp.reason}")
                            errors["total"] += 1
                        continue
            except Exception as exc:
                with lock:
                    if errors["total"] == 0:
                        print(f"debug_error: {exc}")
                    errors["total"] += 1
            else:
                duration = time.perf_counter() - begin
                with lock:
                    latencies.append(duration)

    threads = [threading.Thread(target=worker) for _ in range(concurrency)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    elapsed = time.perf_counter() - start

    if latencies:
        latencies.sort()
        p50 = latencies[int(0.5 * len(latencies))]
        p95 = latencies[min(int(0.95 * len(latencies)), len(latencies) - 1)]
    else:
        p50 = p95 = 0

    print(json.dumps({
        "requests": total_requests,
        "errors": errors["total"],
        "elapsed_sec": round(elapsed, 3),
        "latency_p50_ms": round(p50 * 1000, 2),
        "latency_p95_ms": round(p95 * 1000, 2)
    }))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover
        print(json.dumps({"error": str(exc)}))
        sys.exit(1)
PY

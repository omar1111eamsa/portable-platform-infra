#!/usr/bin/env bash
set -euo pipefail

SERVICE_URL="${SERVICE_URL:-http://localhost:8080}"
CONCURRENCY="${CONCURRENCY:-3}"
REQUESTS="${REQUESTS:-50}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-10}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"
REQUEST_RETRIES="${REQUEST_RETRIES:-5}"

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
import urllib.parse
import urllib.request
import uuid
import http.client

service_url, concurrency, total_requests = sys.argv[1:]
concurrency = int(concurrency)
total_requests = int(total_requests)

request_timeout = float(os.environ.get("REQUEST_TIMEOUT", "10"))
health_timeout = float(os.environ.get("HEALTH_TIMEOUT", "120"))
max_retries = int(os.environ.get("REQUEST_RETRIES", "3"))

register_url = f"{service_url}/internal/auth/register"
login_url = f"{service_url}/internal/auth/login"
validate_url = f"{service_url}/internal/auth/validate-token"
legacy_update_url_template = f"{service_url}/internal/users/{{}}/subscription"
admin_subscription_url_template = f"{service_url}/internal/users/{{}}/subscription"
role_update_url_template = f"{service_url}/internal/users/{{}}/role"
permissions_url_template = f"{service_url}/internal/users/{{}}/permissions"
health_url = f"{service_url}/health"
metrics_url = f"{service_url}/internal/metrics"

VERBOSE = os.environ.get("PERF_VERBOSE", "0").lower() not in {"0", "false", "no", ""}
THROTTLE_SLEEP = float(os.environ.get("PERF_THROTTLE_SLEEP", "0"))

validate_parsed = urllib.parse.urlparse(validate_url)
validate_path = validate_parsed.path or "/"
if validate_parsed.query:
    validate_path += "?" + validate_parsed.query
validate_host = validate_parsed.hostname or "localhost"
validate_port = validate_parsed.port or (443 if validate_parsed.scheme == "https" else 80)
validate_is_https = validate_parsed.scheme == "https"
ValidateConnection = http.client.HTTPSConnection if validate_is_https else http.client.HTTPConnection


def wait_for_health():
    deadline = time.time() + health_timeout
    attempt = 0
    print(f"[perf] Waiting for service health at {health_url} (timeout {health_timeout}s)")
    while time.time() < deadline:
        try:
            attempt += 1
            req = urllib.request.Request(health_url)
            with urllib.request.urlopen(req, timeout=request_timeout) as resp:
                if resp.status == 200:
                    print(f"[perf] Service healthy (attempt {attempt})")
                    return
        except Exception as exc:
            print(f"[perf] Health check attempt {attempt} failed: {exc}")
        time.sleep(1)
    raise RuntimeError("Service did not become healthy within the allotted time")


def json_call(url, payload, method="POST"):
    body_str = json.dumps(payload)
    if VERBOSE:
        print(f"[perf] -> {method} {url} payload={body_str}")
    data = body_str.encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method=method)
    with urllib.request.urlopen(req, timeout=request_timeout) as resp:
        raw = resp.read()
        text = raw.decode() if raw else ""
        if VERBOSE:
            print(f"[perf] <- HTTP {resp.status} {resp.reason if hasattr(resp, 'reason') else ''} body={text}")
        parsed = json.loads(text) if text else {}
        return resp.status, parsed


def main():
    wait_for_health()

    unique = uuid.uuid4().hex
    email = f"perf-{unique}@example.com"
    password = "PerfSmoke123!"

    # Register user
    status, body = json_call(register_url, {
        "email": email,
        "password": password,
        "full_name": "Perf Smoke",
        "role": "user"
    })
    if status not in (200, 201):
        raise RuntimeError(f"Registration failed with HTTP {status}")

    # Upgrade subscription to PRO
    encoded_email = urllib.parse.quote(email, safe="")
    status, _ = json_call(legacy_update_url_template.format(encoded_email), {
        "plan_type": 89,
        "payment_reference": f"PERF-{unique}"
    }, method="PUT")
    if status not in (200, 204):
        raise RuntimeError(f"Legacy subscription update failed with HTTP {status}")

    # Login to get JWT token
    status, login_body = json_call(login_url, {
        "email": email,
        "password": password
    })
    if status != 200:
        raise RuntimeError(f"Login failed with HTTP {status}")
    token = login_body["token"]
    user_id = login_body["user_id"]

    admin_subscription_url = admin_subscription_url_template.format(user_id)
    role_update_url = role_update_url_template.format(user_id)
    permissions_url = permissions_url_template.format(user_id)

    # Admin subscription patch to elevate plan and reset counters
    admin_payload = {
        "plan_name": "ELITE",
        "status": "active",
        "reset_backtests": True,
        "provider_reference": f"ADMIN-{unique}"
    }
    status, admin_body = json_call(admin_subscription_url, admin_payload, method="PATCH")
    if status != 200:
        raise RuntimeError(f"admin subscription update failed with HTTP {status}")
    plan_name = admin_body.get("subscription", {}).get("plan_name", "")
    if plan_name != "ELITE":
        raise RuntimeError(f"unexpected admin subscription plan {plan_name!r}")

    # Role update to support
    status, role_body = json_call(role_update_url, {
        "role": "support",
        "is_active": True
    }, method="PATCH")
    if status != 200:
        raise RuntimeError(f"role update failed with HTTP {status}")
    if role_body.get("role") != "support":
        raise RuntimeError("role update did not persist new role")

    payload = json.dumps({"token": token}).encode()
    headers = {
        "Content-Type": "application/json",
        "Connection": "keep-alive"
    }

    latencies = []
    state = {"count": 0}
    errors = {"total": 0}
    lock = threading.Lock()

    start = time.perf_counter()

    def worker():
        conn = None
        try:
            while True:
                with lock:
                    if state["count"] >= total_requests:
                        break
                    state["count"] += 1
                    iteration = state["count"]
                log_prefix = f"[perf][worker-{threading.get_ident()}][#{iteration}]"
                attempt = 0
                success = False
                while attempt <= max_retries and not success:
                    attempt += 1
                    begin = time.perf_counter()
                    if VERBOSE:
                        print(f"{log_prefix} -> POST /internal/auth/validate-token (attempt {attempt})")
                    try:
                        if conn is None:
                            conn = ValidateConnection(validate_host, validate_port, timeout=request_timeout)
                        conn.request("POST", validate_path, body=payload, headers=headers)
                        resp = conn.getresponse()
                        try:
                            status = resp.status
                            resp.read()
                        finally:
                            resp.close()
                        if status != 200:
                            raise RuntimeError(f"HTTP {status}")
                        success = True
                        duration = time.perf_counter() - begin
                        if VERBOSE:
                            print(f"{log_prefix} <- success {round(duration * 1000, 2)} ms")
                        with lock:
                            latencies.append(duration)
                    except Exception as exc:
                        if conn is not None:
                            try:
                                conn.close()
                            except Exception:
                                pass
                            conn = None
                        if VERBOSE or attempt > max_retries:
                            print(f"{log_prefix} validate exception: {exc}")
                        if attempt > max_retries:
                            with lock:
                                if errors["total"] == 0:
                                    print(f"debug_error: {exc}")
                                errors["total"] += 1
                        else:
                            time.sleep(0.1)

                if not success:
                    continue

                if THROTTLE_SLEEP > 0:
                    time.sleep(THROTTLE_SLEEP)

                if iteration % 5 == 0:
                    try:
                        perm_req = urllib.request.Request(permissions_url)
                        with urllib.request.urlopen(perm_req, timeout=request_timeout) as perm_resp:
                            if VERBOSE:
                                print(f"{log_prefix} permissions -> HTTP {perm_resp.status}")
                    except Exception as exc:
                        if VERBOSE:
                            print(f"{log_prefix} warning: permissions fetch failed: {exc}")
        finally:
            if conn is not None:
                try:
                    conn.close()
                except Exception:
                    pass

    threads = [threading.Thread(target=worker) for _ in range(concurrency)]
    print(f"[perf] Launching {concurrency} workers for {total_requests} validate calls")
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

    final_plan = None
    final_role = None
    try:
        perm_req = urllib.request.Request(permissions_url)
        with urllib.request.urlopen(perm_req, timeout=request_timeout) as perm_resp:
            if perm_resp.status == 200:
                perm_body = json.load(perm_resp)
                final_plan = perm_body.get("plan_name")
                final_role = perm_body.get("role")
    except Exception:
        pass

    throughput = total_requests / elapsed if elapsed > 0 else 0.0

    result = {
        "requests": total_requests,
        "errors": errors["total"],
        "elapsed_sec": round(elapsed, 3),
        "latency_p50_ms": round(p50 * 1000, 2),
        "latency_p95_ms": round(p95 * 1000, 2),
        "throughput_rps": round(throughput, 2)
    }
    if final_plan is not None:
        result["final_plan"] = final_plan
    if final_role is not None:
        result["final_role"] = final_role

    try:
        req = urllib.request.Request(metrics_url)
        with urllib.request.urlopen(req, timeout=request_timeout) as resp:
            if resp.status == 200:
                result["metrics"] = json.load(resp)
    except Exception as exc:
        print(f"[perf] warning: failed to fetch metrics: {exc}")

    print(json.dumps(result))

    latency_target = float(os.environ.get("P95_TARGET_MS", "50"))
    throughput_target = float(os.environ.get("THROUGHPUT_TARGET_RPS", "1000"))

    if latency_target > 0 and result["latency_p95_ms"] > latency_target:
        raise RuntimeError(f"P95 latency {result['latency_p95_ms']}ms exceeded target {latency_target}ms")
    if throughput_target > 0 and throughput < throughput_target:
        raise RuntimeError(f"Throughput {throughput:.2f} rps below target {throughput_target} rps")
    print("[perf] Smoke test complete")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover
        print(json.dumps({"error": str(exc)}))
        sys.exit(1)
PY

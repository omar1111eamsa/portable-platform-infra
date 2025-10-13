#!/usr/bin/env python3
"""
Integration test exercising the full register → subscription update → login → validate → permissions flow.
Designed to run inside the docker-compose `integration_tests` service without external dependencies.
"""

import json
import os
import sys
import time
import uuid
from urllib import error, parse, request


BASE_URL = os.environ.get("SERVICE_BASE_URL", "http://localhost:8080").rstrip("/")
TIMEOUT = float(os.environ.get("REQUEST_TIMEOUT", "5"))


def http_request(method: str, path: str, payload: dict | None = None) -> tuple[int, dict, str]:
    """Perform an HTTP request using the standard library."""
    url = f"{BASE_URL}{path}"
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"

    req = request.Request(url, data=data, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=TIMEOUT) as resp:
            body = resp.read().decode() if resp.length != 0 else ""
            parsed = json.loads(body) if body else {}
            return resp.getcode(), parsed, body
    except error.HTTPError as exc:
        body = exc.read().decode() if exc.length != 0 else ""
        parsed = json.loads(body) if body else {}
        return exc.code, parsed, body
    except error.URLError as exc:
        raise RuntimeError(f"Network error calling {url}: {exc}") from exc


def wait_for_service(timeout_seconds: float = 120.0):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            status, _, _ = http_request("GET", "/health")
            if status == 200:
                return
        except RuntimeError:
            pass
        time.sleep(1)
    raise RuntimeError(f"Service did not become healthy within {timeout_seconds} seconds")


def ensure_status(actual: int, expected: int, body: str):
    if actual != expected:
        raise AssertionError(f"Expected HTTP {expected}, got {actual}: {body}")


def run_flow():
    unique = uuid.uuid4().hex
    email = f"integration-{unique}@example.com"
    password = "IntegrationPass!2"

    # Register
    status, register_body, raw = http_request(
        "POST",
        "/internal/auth/register",
        {
            "email": email,
            "password": password,
            "full_name": "Integration Bot",
            "role": "user",
        },
    )
    ensure_status(status, 201, raw)
    user_id = register_body["user_id"]

    # Upgrade subscription to PRO
    encoded_email = parse.quote(email, safe="")
    status, _, raw = http_request(
        "PUT",
        f"/internal/users/{encoded_email}/subscription",
        {
            "plan_type": 89,
            "payment_reference": f"INT-{unique}",
        },
    )
    ensure_status(status, 200, raw)

    # Login
    status, login_body, raw = http_request(
        "POST",
        "/internal/auth/login",
        {
            "email": email,
            "password": password,
        },
    )
    ensure_status(status, 200, raw)
    token = login_body["token"]
    assert login_body["plan"] == "PRO"
    assert login_body["user_id"] == user_id

    # Validate token
    status, validation, raw = http_request(
        "POST",
        "/internal/auth/validate-token",
        {"token": token},
    )
    ensure_status(status, 200, raw)
    assert validation["valid"] is True
    assert validation["user_id"] == user_id
    assert validation["plan_name"] == "PRO"
    assert validation["permissions"]["can_use_api"] is True

    # Permissions GET
    status, perms, raw = http_request(
        "GET",
        f"/internal/users/{user_id}/permissions",
    )
    ensure_status(status, 200, raw)
    assert perms["user_id"] == user_id
    assert perms["plan_name"] == "PRO"
    assert perms["plan_status"] == "active"
    assert perms["quotas"]["backtests_per_day_limit"] >= 50

    # Admin subscription update (promote to ELITE and reset quotas)
    status, admin_sub, raw = http_request(
        "PATCH",
        f"/internal/users/{user_id}/subscription",
        {
            "plan_name": "elite",
            "status": "active",
            "reset_backtests": True,
            "provider_reference": "INT-ADMIN"
        },
    )
    ensure_status(status, 200, raw)
    assert admin_sub["subscription"]["plan_name"] == "ELITE"
    assert admin_sub["subscription"]["backtests_used_today"] == 0

    # Role update to support
    status, role_resp, raw = http_request(
        "PATCH",
        f"/internal/users/{user_id}/role",
        {
            "role": "support",
            "is_active": True
        },
    )
    ensure_status(status, 200, raw)
    assert role_resp["role"] == "support"
    assert role_resp["is_active"] is True

    # Permissions after updates
    status, perms_after, raw = http_request(
        "GET",
        f"/internal/users/{user_id}/permissions",
    )
    ensure_status(status, 200, raw)
    assert perms_after["plan_name"] == "ELITE"
    assert perms_after["role"] == "support"

    # Metrics snapshot includes the exercised endpoints
    status, metrics_body, raw = http_request("GET", "/internal/metrics")
    ensure_status(status, 200, raw)
    assert "auth.login" in metrics_body
    assert metrics_body["auth.login"]["successes"] >= 1


def main():
    wait_for_service()
    run_flow()
    print("Integration flow completed successfully.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover
        print(f"[integration-test] failure: {exc}", file=sys.stderr)
        sys.exit(1)

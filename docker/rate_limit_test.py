#!/usr/bin/env python3
"""
rate_limit_test.py

Purpose:
  Stress a single HTTP(S) endpoint to test rate-limiting behavior.
  - Sends N total requests with configurable concurrency.
  - Measures HTTP status codes, latencies, errors, and reports percentiles.
  - Detects and reports 429 responses separately.
  - Works with JSON request bodies and optional Authorization header.

Usage:
  chmod +x rate_limit_test.py
  ./rate_limit_test.py --url http://localhost:8080/internal/auth/validate-token \
                       --method POST \
                       --data '{"token":"..."}' \
                       --concurrency 10 \
                       --requests 100 \
                       --timeout 5

Options:
  --url           endpoint URL (required)
  --method        HTTP method (default POST)
  --data          JSON data string (optional)
  --data-file     Path to file containing request body (use instead of --data)
  --concurrency   number of concurrent worker threads (default: 10)
  --requests      total number of requests to send (default: 100)
  --timeout       per-request timeout in seconds (default: 5)
  --stop-on-429   stop the test immediately when the first 429 is observed (flag)
  --save-body     save example response body to file "example_response.txt" (flag)
  -h, --help

Notes / safety:
  - Don't run aggressively against production systems without permission.
  - The script deliberately creates new connections per request to simulate real clients.
"""

import argparse
import concurrent.futures
import http.client
import json
import sys
import time
import urllib.parse
from collections import Counter, defaultdict
from statistics import mean, median

def parse_args():
    p = argparse.ArgumentParser(description="Rate limit testing tool (standard library only).")
    p.add_argument("--url", required=True, help="Target endpoint URL (http://host:port/path or https://...)")
    p.add_argument("--method", default="POST", help="HTTP method (default POST)")
    p.add_argument("--data", help="Request body (JSON string). Mutually exclusive with --data-file.")
    p.add_argument("--data-file", help="Path to file containing request body (JSON/text).")
    p.add_argument("--concurrency", type=int, default=10, help="Number of concurrent worker threads (default 10)")
    p.add_argument("--requests", type=int, default=100, help="Total number of requests to send (default 100)")
    p.add_argument("--timeout", type=float, default=5.0, help="Per-request timeout in seconds (default 5)")
    p.add_argument("--stop-on-429", action="store_true", help="Stop test immediately when first 429 is observed")
    p.add_argument("--save-body", action="store_true", help='Save one example response body to "example_response.txt"')
    return p.parse_args()

def prepare_body(args):
    if args.data_file:
        with open(args.data_file, "rb") as f:
            return f.read()
    if args.data:
        return args.data.encode("utf-8")
    return b""

def make_request_once(parsed, method, headers, body, timeout):
    """Send one HTTP request and return tuple(status, latency_sec, response_body_or_error)."""
    start = time.perf_counter()
    conn = None
    try:
        if parsed.scheme == "https":
            conn = http.client.HTTPSConnection(parsed.hostname, parsed.port or 443, timeout=timeout)
        else:
            conn = http.client.HTTPConnection(parsed.hostname, parsed.port or 80, timeout=timeout)

        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query

        conn.request(method, path, body=body, headers=headers)
        resp = conn.getresponse()
        resp_body = resp.read()  # bytes
        latency = time.perf_counter() - start
        status = resp.status
        return (status, latency, resp_body)
    except Exception as e:
        latency = time.perf_counter() - start
        return ("ERR", latency, str(e).encode("utf-8"))
    finally:
        try:
            if conn:
                conn.close()
        except Exception:
            pass

def worker_task(idx, parsed, method, headers, body, timeout):
    # wrapper so each call is independent for the thread pool
    return make_request_once(parsed, method, headers, body, timeout)

def percentile(sorted_list, p):
    if not sorted_list:
        return None
    k = (len(sorted_list)-1) * (p/100.0)
    f = int(k)
    c = f + 1
    if c >= len(sorted_list):
        return sorted_list[-1]
    d0 = sorted_list[f] * (c - k)
    d1 = sorted_list[c] * (k - f)
    return d0 + d1

def main():
    args = parse_args()
    body = prepare_body(args)
    parsed = urllib.parse.urlparse(args.url)
    method = args.method.upper()

    # Build headers (JSON if we have a body)
    headers = {}
    if body:
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = str(len(body))
    # Authorization: allow user to set TOKEN env var
    import os
    token = os.getenv("TOKEN") or os.getenv("AUTH_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token

    total = args.requests
    concurrency = max(1, args.concurrency)
    timeout = args.timeout

    print("Rate limit test starting:")
    print("  URL:         ", args.url)
    print("  Method:      ", method)
    print("  Concurrency: ", concurrency)
    print("  Requests:    ", total)
    print("  Timeout:     ", timeout)
    print("  Stop on 429: ", bool(args.stop_on_429))
    if token:
        print("  Authorization: Bearer token from $TOKEN present")
    else:
        print("  Authorization: none")

    results = []
    status_counter = Counter()
    errors = []
    latencies = []
    example_body_saved = False
    example_saved_path = "example_response.txt"

    start_all = time.perf_counter()

    # Use thread pool and submit tasks in batches to control concurrency
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as ex:
        futures = []
        stop = False
        submitted = 0

        # Submit all tasks but we will check for stop conditions while consuming results.
        for i in range(total):
            futures.append(ex.submit(worker_task, i, parsed, method, headers, body, timeout))
            submitted += 1

        # Now iterate as completed to collect results as they finish
        for fut in concurrent.futures.as_completed(futures):
            try:
                status, latency, resp_body = fut.result()
            except Exception as e:
                status = "ERR"
                latency = 0.0
                resp_body = str(e).encode("utf-8")

            # categorize
            if status == "ERR":
                status_counter["ERR"] += 1
                errors.append(resp_body.decode("utf-8", errors="replace"))
            else:
                status_counter[str(status)] += 1

            latencies.append(latency)
            results.append((status, latency))

            # optionally save one response body for inspection
            if args.save_body and not example_body_saved:
                try:
                    with open(example_saved_path, "wb") as f:
                        f.write(resp_body if isinstance(resp_body, (bytes, bytearray)) else str(resp_body).encode("utf-8"))
                    example_body_saved = True
                except Exception as e:
                    print("Warning: failed to save example response:", e)

            # If stop-on-429 and we saw a 429, try to cancel the remaining futures
            if args.stop_on_429 and status == 429:
                print("Observed 429, stopping early as requested (--stop-on-429).")
                stop = True
                # Note: we cannot reliably cancel already running futures; just break and summarize
                break

    duration = time.perf_counter() - start_all
    total_done = len(results)
    ok_count = sum(v for k,v in status_counter.items() if k.isdigit() and 200 <= int(k) < 300)
    code429 = status_counter.get("429", 0)
    other_errors = sum(v for k,v in status_counter.items() if (not k.isdigit()) or (int(k) >= 300 and int(k) != 429))

    # latency stats
    lat_sorted = sorted(latencies)
    p50 = percentile(lat_sorted, 50)
    p90 = percentile(lat_sorted, 90)
    p99 = percentile(lat_sorted, 99)
    avg = mean(lat_sorted) if lat_sorted else None
    med = median(lat_sorted) if lat_sorted else None

    print("\n=== TEST SUMMARY ===")
    print(f"Total requested:    {total}")
    print(f"Total completed:    {total_done}")
    print(f"Elapsed (wall):     {duration:.3f}s")
    print(f"Requests/sec (avg): {total_done / duration:.2f}")

    print("\nStatus codes:")
    for code, cnt in sorted(status_counter.items(), key=lambda x: (-x[1], x[0])):
        print(f"  {code:>3}: {cnt}")

    print("\nLatency (seconds):")
    if lat_sorted:
        print(f"  avg : {avg:.4f}")
        print(f"  p50 : {p50:.4f}")
        print(f"  p90 : {p90:.4f}")
        print(f"  p99 : {p99:.4f}")
    else:
        print("  no latency data")

    if args.save_body and example_body_saved:
        print(f'\nAn example response was saved to "{example_saved_path}"')

    if errors:
        print("\nSome errors (first 5):")
        for e in errors[:5]:
            print(" -", e.strip())

    # Simple judgement about rate limit
    print("\nInterpretation:")
    if code429 > 0:
        print(f"  -> Detected {code429} 429 responses. Rate-limiter is active for this endpoint / token.")
    else:
        print("  -> No 429s detected. Either the rate limit wasn't reached or endpoint doesn't return 429 for throttling.")
        print("     Consider increasing request rate or lowering plan limits for testing.")

    print("\nDone.")
    return 0

if __name__ == "__main__":
    sys.exit(main())

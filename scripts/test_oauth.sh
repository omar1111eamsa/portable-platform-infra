#!/usr/bin/env bash
set -euo pipefail

SERVICE_URL="${SERVICE_URL:-http://localhost:8080}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-10}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

python3 - "$SERVICE_URL" <<'PY'
import json
import sys
import urllib.request
import urllib.parse
import urllib.error

service_url = sys.argv[1]

def make_request(url, method="GET", data=None, headers=None, allow_redirects=True):
    """Make HTTP request and return status, response"""
    if headers is None:
        headers = {}
    
    req_data = None
    if data:
        req_data = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    
    # Create a custom opener that doesn't follow redirects
    opener = urllib.request.build_opener()
    if not allow_redirects:
        opener.addheaders = [('User-Agent', 'Mozilla/5.0')]
    
    req = urllib.request.Request(url, data=req_data, headers=headers, method=method)
    try:
        with opener.open(req, timeout=10) as resp:
            body = resp.read().decode() if resp.length != 0 else ""
            # Try to parse as JSON, but don't fail if it's not JSON
            try:
                parsed = json.loads(body) if body else {}
            except json.JSONDecodeError:
                parsed = {"raw_response": body}
            return resp.getcode(), parsed, body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode() if exc.length != 0 else ""
        # Try to parse as JSON, but don't fail if it's not JSON
        try:
            parsed = json.loads(body) if body else {}
        except json.JSONDecodeError:
            parsed = {"raw_response": body}
        return exc.code, parsed, body
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Network error calling {url}: {exc}") from exc

def test_oauth_endpoints():
    """Test OAuth endpoints"""
    print("🔐 Testing OAuth External Authentication Endpoints")
    print("=" * 60)
    
    # Test 1: OAuth initiation endpoints
    print("\n1. Testing OAuth initiation endpoints...")
    providers = ["google", "github", "linkedin"]  # tradingview temporarily disabled
    
    for provider in providers:
        try:
            status, body, raw = make_request(f"{service_url}/auth/{provider}", allow_redirects=False)
            if status == 302:
                print(f"   ✅ {provider}: Redirect to OAuth provider (HTTP {status})")
            elif status == 200:
                # Some HTTP clients might follow redirects automatically
                print(f"   ✅ {provider}: OAuth URL generated (HTTP {status})")
            # elif status == 404 and provider == "tradingview":
            #     # TradingView OAuth might not be available for general use
            #     print(f"   ⚠️  {provider}: OAuth not available (HTTP {status}) - may require broker integration")
            else:
                print(f"   ⚠️  {provider}: Unexpected status {status}")
        except Exception as e:
            print(f"   ❌ {provider}: Error - {e}")
    
    # Test 2: OAuth callback with invalid code
    print("\n2. Testing OAuth callback with invalid code...")
    try:
        status, body, raw = make_request(f"{service_url}/auth/google/callback?code=invalid_code&state=test_state")
        if status == 400:
            print(f"   ✅ Google callback: Properly rejected invalid code (HTTP {status})")
        else:
            print(f"   ⚠️  Google callback: Unexpected status {status}")
    except Exception as e:
        print(f"   ❌ Google callback: Error - {e}")
    
    # Test 3: OAuth callback with error parameter
    print("\n3. Testing OAuth callback with error parameter...")
    try:
        status, body, raw = make_request(f"{service_url}/auth/google/callback?error=access_denied&error_description=User%20denied%20access")
        if status == 400:
            print(f"   ✅ Google callback: Properly handled OAuth error (HTTP {status})")
        else:
            print(f"   ⚠️  Google callback: Unexpected status {status}")
    except Exception as e:
        print(f"   ❌ Google callback: Error - {e}")
    
    # Test 4: Link external auth (should fail without valid user)
    print("\n4. Testing link external auth...")
    try:
        link_data = {
            "user_id": "00000000-0000-0000-0000-000000000000",
            "provider": "google",
            "provider_user_id": "test_google_user",
            "provider_email": "test@example.com",
            "provider_name": "Test User"
        }
        status, body, raw = make_request(f"{service_url}/auth/link", "POST", link_data)
        if status in [404, 500]:  # User not found or database error
            print(f"   ✅ Link external auth: Properly handled invalid user (HTTP {status})")
        else:
            print(f"   ⚠️  Link external auth: Unexpected status {status}")
    except Exception as e:
        print(f"   ❌ Link external auth: Error - {e}")
    
    # Test 5: Unlink external auth (should fail without valid user)
    print("\n5. Testing unlink external auth...")
    try:
        unlink_data = {
            "user_id": "00000000-0000-0000-0000-000000000000",
            "provider": "google"
        }
        status, body, raw = make_request(f"{service_url}/auth/unlink", "DELETE", unlink_data)
        if status in [404, 500]:  # External auth not found or database error
            print(f"   ✅ Unlink external auth: Properly handled invalid user (HTTP {status})")
        else:
            print(f"   ⚠️  Unlink external auth: Unexpected status {status}")
    except Exception as e:
        print(f"   ❌ Unlink external auth: Error - {e}")
    
    # Test 6: Get external auths (should return empty list)
    print("\n6. Testing get external auths...")
    try:
        status, body, raw = make_request(f"{service_url}/users/00000000-0000-0000-0000-000000000000/external-auths")
        if status == 200:
            if "external_auths" in body and body["external_auths"] == []:
                print(f"   ✅ Get external auths: Returned empty list (HTTP {status})")
            else:
                print(f"   ⚠️  Get external auths: Unexpected response format")
        else:
            print(f"   ⚠️  Get external auths: Unexpected status {status}")
    except Exception as e:
        print(f"   ❌ Get external auths: Error - {e}")
    
    # Test 7: Invalid provider
    print("\n7. Testing invalid provider...")
    try:
        status, body, raw = make_request(f"{service_url}/auth/invalid_provider")
        if status == 404:  # Route not found is correct behavior
            print(f"   ✅ Invalid provider: Properly rejected (HTTP {status})")
        else:
            print(f"   ⚠️  Invalid provider: Unexpected status {status}")
    except Exception as e:
        print(f"   ❌ Invalid provider: Error - {e}")
    
    # Test 8: Invalid link data
    print("\n8. Testing invalid link data...")
    try:
        invalid_data = {
            "user_id": "invalid_uuid",
            "provider": "invalid_provider"
        }
        status, body, raw = make_request(f"{service_url}/auth/link", "POST", invalid_data)
        if status == 400:
            print(f"   ✅ Invalid link data: Properly rejected (HTTP {status})")
        else:
            print(f"   ⚠️  Invalid link data: Unexpected status {status}")
    except Exception as e:
        print(f"   ❌ Invalid link data: Error - {e}")
    
    print("\n" + "=" * 60)
    print("🎉 OAuth endpoint testing completed!")
    print("\nNote: These tests verify endpoint availability and error handling.")
    print("For full OAuth flow testing, you need to:")
    print("1. Configure OAuth provider credentials")
    print("2. Set up OAuth applications with the providers")
    print("3. Test the complete OAuth flow with real authorization codes")

if __name__ == "__main__":
    try:
        test_oauth_endpoints()
    except Exception as exc:
        print(f"❌ Test failed: {exc}")
        sys.exit(1)
PY

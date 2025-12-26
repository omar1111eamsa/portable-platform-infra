#!/bin/bash

# =============================================================================
# CQOS User Management & Subscription Service - Robust Metrics Testing Script
# =============================================================================
# This script tests all available endpoints and metrics to verify service health
# and performance after optimizations.
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SERVICE_URL="http://localhost:8080"
TIMEOUT=10
MAX_RETRIES=3

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# =============================================================================
# Utility Functions
# =============================================================================

print_header() {
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED_TESTS++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((FAILED_TESTS++))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Test function with retry logic
test_endpoint() {
    local endpoint="$1"
    local expected_status="$2"
    local description="$3"
    local method="${4:-GET}"
    local data="${5:-}"
    
    ((TOTAL_TESTS++))
    
    echo -e "\n${PURPLE}Testing: $description${NC}"
    echo -e "Endpoint: $method $endpoint"
    
    local retry_count=0
    local success=false
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        local response
        local status_code
        
        if [ "$method" = "POST" ] && [ -n "$data" ]; then
            response=$(curl -s -w "\n%{http_code}" -X POST \
                -H "Content-Type: application/json" \
                -d "$data" \
                --connect-timeout $TIMEOUT \
                --max-time $TIMEOUT \
                "$SERVICE_URL$endpoint" 2>/dev/null || echo -e "\n000")
        else
            response=$(curl -s -w "\n%{http_code}" \
                --connect-timeout $TIMEOUT \
                --max-time $TIMEOUT \
                "$SERVICE_URL$endpoint" 2>/dev/null || echo -e "\n000")
        fi
        
        status_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | head -n -1)
        
        if [ "$status_code" = "$expected_status" ]; then
            success=true
            break
        fi
        
        ((retry_count++))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}Retry $retry_count/$MAX_RETRIES...${NC}"
            sleep 1
        fi
    done
    
    if [ "$success" = true ]; then
        print_success "$description (Status: $status_code)"
        if [ -n "$response_body" ] && [ "$response_body" != "null" ]; then
            echo -e "${CYAN}Response: $response_body${NC}"
        fi
    else
        print_error "$description (Expected: $expected_status, Got: $status_code)"
        if [ -n "$response_body" ]; then
            echo -e "${RED}Response: $response_body${NC}"
        fi
    fi
}

# Performance test function
test_performance() {
    local endpoint="$1"
    local description="$2"
    local concurrency="${3:-10}"
    local requests="${4:-100}"
    
    ((TOTAL_TESTS++))
    
    echo -e "\n${PURPLE}Performance Test: $description${NC}"
    echo -e "Endpoint: $endpoint (Concurrency: $concurrency, Requests: $requests)"
    
    # Create test payload if needed
    local payload_file="/tmp/metrics_test_payload.json"
    echo '{"token":"test-token-for-metrics"}' > "$payload_file"
    
    local result
    if [[ "$endpoint" == *"validate-token"* ]]; then
        result=$(ab -n $requests -c $concurrency \
            -H "Content-Type: application/json" \
            -p "$payload_file" \
            -q "$SERVICE_URL$endpoint" 2>/dev/null || echo "FAILED")
    else
        result=$(ab -n $requests -c $concurrency \
            -q "$SERVICE_URL$endpoint" 2>/dev/null || echo "FAILED")
    fi
    
    if [ "$result" = "FAILED" ]; then
        print_error "$description - Performance test failed"
    else
        local rps=$(echo "$result" | grep "Requests per second" | awk '{print $4}' | cut -d'[' -f1)
        local p95=$(echo "$result" | grep "95%" | awk '{print $2}')
        
        if [ -n "$rps" ] && [ -n "$p95" ]; then
            print_success "$description - RPS: $rps, P95: ${p95}ms"
        else
            print_warning "$description - Performance test completed but metrics unclear"
        fi
    fi
    
    # Cleanup
    rm -f "$payload_file"
}

# =============================================================================
# Main Testing Functions
# =============================================================================

test_basic_endpoints() {
    print_header "BASIC ENDPOINT TESTS"
    
    # Health check
    test_endpoint "/health" "200" "Health Check"
    
    # Metrics endpoint
    test_endpoint "/internal/metrics" "200" "Internal Metrics"
    
    # API endpoints (should return 401 for unauthorized)
    test_endpoint "/api/v1/users/me" "401" "User Profile (Unauthorized)"
    test_endpoint "/api/v1/subscriptions" "401" "Subscriptions (Unauthorized)"
}

test_auth_endpoints() {
    print_header "AUTHENTICATION ENDPOINT TESTS"
    
    # Test token validation with invalid token
    test_endpoint "/internal/auth/validate-token" "401" "Token Validation (Invalid Token)" "POST" '{"token":"invalid-token"}'
    
    # Test token validation with malformed JSON
    test_endpoint "/internal/auth/validate-token" "400" "Token Validation (Malformed JSON)" "POST" '{"invalid":"json'
    
    # Test token validation with missing token
    test_endpoint "/internal/auth/validate-token" "400" "Token Validation (Missing Token)" "POST" '{}'
}

test_performance_endpoints() {
    print_header "PERFORMANCE TESTS"
    
    # Test health endpoint performance
    test_performance "/health" "Health Endpoint Performance" 10 100
    
    # Test metrics endpoint performance
    test_performance "/internal/metrics" "Metrics Endpoint Performance" 5 50
    
    # Test token validation performance
    test_performance "/internal/auth/validate-token" "Token Validation Performance" 10 100
}

test_service_health() {
    print_header "SERVICE HEALTH CHECKS"
    
    # Check if service is responding
    local response=$(curl -s --connect-timeout 5 --max-time 5 "$SERVICE_URL/health" 2>/dev/null || echo "FAILED")
    
    if [ "$response" = "FAILED" ]; then
        print_error "Service is not responding"
        return 1
    else
        print_success "Service is responding"
    fi
    
    # Check response time
    local response_time=$(curl -s -w "%{time_total}" -o /dev/null --connect-timeout 5 --max-time 5 "$SERVICE_URL/health" 2>/dev/null || echo "FAILED")
    
    if [ "$response_time" != "FAILED" ]; then
        local time_ms=$(echo "$response_time * 1000" | bc -l 2>/dev/null || echo "0")
        print_info "Response time: ${time_ms}ms"
        
        if (( $(echo "$time_ms < 100" | bc -l 2>/dev/null || echo "0") )); then
            print_success "Response time is excellent (< 100ms)"
        elif (( $(echo "$time_ms < 500" | bc -l 2>/dev/null || echo "0") )); then
            print_success "Response time is good (< 500ms)"
        else
            print_warning "Response time is slow (> 500ms)"
        fi
    fi
}

test_error_handling() {
    print_header "ERROR HANDLING TESTS"
    
    # Test non-existent endpoints
    test_endpoint "/nonexistent" "404" "Non-existent Endpoint"
    test_endpoint "/api/v1/invalid" "404" "Invalid API Endpoint"
    
    # Test malformed requests
    test_endpoint "/internal/auth/validate-token" "400" "Empty POST Body" "POST" ""
    test_endpoint "/internal/auth/validate-token" "400" "Invalid JSON" "POST" '{"invalid":}'
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    print_header "CQOS USER MANAGEMENT & SUBSCRIPTION SERVICE - ROBUST METRICS TESTING"
    echo -e "${CYAN}Testing service at: $SERVICE_URL${NC}"
    echo -e "${CYAN}Timeout: ${TIMEOUT}s, Max Retries: $MAX_RETRIES${NC}"
    echo ""
    
    # Check if service is running
    print_info "Checking if service is running..."
    if ! curl -s --connect-timeout 5 --max-time 5 "$SERVICE_URL/health" >/dev/null 2>&1; then
        print_error "Service is not running or not accessible at $SERVICE_URL"
        print_info "Please start the service with: make docker-run"
        exit 1
    fi
    
    print_success "Service is running and accessible"
    
    # Run all tests
    test_service_health
    test_basic_endpoints
    test_auth_endpoints
    test_performance_endpoints
    test_error_handling
    
    # Print final results
    print_header "TEST RESULTS SUMMARY"
    echo -e "${CYAN}Total Tests: $TOTAL_TESTS${NC}"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        echo -e "${CYAN}Success Rate: ${success_rate}%${NC}"
        
        if [ $FAILED_TESTS -eq 0 ]; then
            print_success "All tests passed! Service is healthy and optimized."
            exit 0
        elif [ $success_rate -ge 80 ]; then
            print_warning "Most tests passed. Service is mostly healthy."
            exit 0
        else
            print_error "Multiple tests failed. Service may have issues."
            exit 1
        fi
    else
        print_warning "No tests were executed."
        exit 1
    fi
}

# Run main function
main "$@"

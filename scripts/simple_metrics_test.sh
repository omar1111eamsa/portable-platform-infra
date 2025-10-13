#!/bin/bash

# Simple Metrics Test Script for CQOS User Management Service
# Tests basic endpoints and performance

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVICE_URL="http://localhost:8080"

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}CQOS USER MANAGEMENT SERVICE - SIMPLE METRICS TEST${NC}"
echo -e "${BLUE}=============================================================================${NC}"

# Test 1: Health Check
echo -e "\n${YELLOW}1. Testing Health Endpoint${NC}"
health_response=$(curl -s "$SERVICE_URL/health" 2>/dev/null || echo "FAILED")
if [ "$health_response" != "FAILED" ]; then
    echo -e "${GREEN}✅ Health endpoint working: $health_response${NC}"
else
    echo -e "${RED}❌ Health endpoint failed${NC}"
    exit 1
fi

# Test 2: Metrics Endpoint
echo -e "\n${YELLOW}2. Testing Metrics Endpoint${NC}"
metrics_response=$(curl -s "$SERVICE_URL/internal/metrics" 2>/dev/null || echo "FAILED")
if [ "$metrics_response" != "FAILED" ]; then
    echo -e "${GREEN}✅ Metrics endpoint working: $metrics_response${NC}"
else
    echo -e "${RED}❌ Metrics endpoint failed${NC}"
fi

# Test 3: Token Validation Endpoint
echo -e "\n${YELLOW}3. Testing Token Validation Endpoint${NC}"
token_response=$(curl -s -X POST -H "Content-Type: application/json" -d '{"token":"invalid-token"}' "$SERVICE_URL/internal/auth/validate-token" 2>/dev/null || echo "FAILED")
if [ "$token_response" != "FAILED" ]; then
    echo -e "${GREEN}✅ Token validation endpoint working: $token_response${NC}"
else
    echo -e "${RED}❌ Token validation endpoint failed${NC}"
fi

# Test 4: Performance Test
echo -e "\n${YELLOW}4. Testing Performance (10 requests, 5 concurrent)${NC}"
echo '{"token":"test-token"}' > /tmp/test_payload.json
perf_result=$(ab -n 10 -c 5 -H "Content-Type: application/json" -p /tmp/test_payload.json -q "$SERVICE_URL/internal/auth/validate-token" 2>/dev/null || echo "FAILED")
rm -f /tmp/test_payload.json

if [ "$perf_result" != "FAILED" ]; then
    rps=$(echo "$perf_result" | grep "Requests per second" | awk '{print $4}' | cut -d'[' -f1)
    p95=$(echo "$perf_result" | grep "95%" | awk '{print $2}')
    echo -e "${GREEN}✅ Performance test completed${NC}"
    echo -e "${GREEN}   RPS: $rps${NC}"
    echo -e "${GREEN}   P95: ${p95}ms${NC}"
else
    echo -e "${RED}❌ Performance test failed${NC}"
fi

# Test 5: Response Time
echo -e "\n${YELLOW}5. Testing Response Time${NC}"
response_time=$(curl -s -w "%{time_total}" -o /dev/null "$SERVICE_URL/health" 2>/dev/null || echo "FAILED")
if [ "$response_time" != "FAILED" ]; then
    time_ms=$(echo "$response_time * 1000" | bc -l 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Response time: ${time_ms}ms${NC}"
    
    if (( $(echo "$time_ms < 100" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "${GREEN}   Excellent response time (< 100ms)${NC}"
    elif (( $(echo "$time_ms < 500" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "${GREEN}   Good response time (< 500ms)${NC}"
    else
        echo -e "${YELLOW}   Slow response time (> 500ms)${NC}"
    fi
else
    echo -e "${RED}❌ Response time test failed${NC}"
fi

echo -e "\n${BLUE}=============================================================================${NC}"
echo -e "${BLUE}METRICS TEST COMPLETED${NC}"
echo -e "${BLUE}=============================================================================${NC}"

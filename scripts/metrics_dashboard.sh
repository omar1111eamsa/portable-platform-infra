#!/bin/bash

# =============================================================================
# CQOS User Management & Subscription Service - Metrics Dashboard
# =============================================================================
# Real-time monitoring dashboard for service metrics and performance
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

SERVICE_URL="http://localhost:8080"
REFRESH_INTERVAL=5

# Function to clear screen and show header
clear_screen() {
    clear
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${WHITE}🚀 CQOS USER MANAGEMENT & SUBSCRIPTION SERVICE - METRICS DASHBOARD${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${CYAN}Service URL: $SERVICE_URL${NC}"
    echo -e "${CYAN}Refresh Interval: ${REFRESH_INTERVAL}s${NC}"
    echo -e "${CYAN}Last Updated: $(date)${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
}

# Function to get service health
get_health() {
    local response=$(curl -s --connect-timeout 2 --max-time 2 "$SERVICE_URL/health" 2>/dev/null || echo "FAILED")
    if [ "$response" = "FAILED" ]; then
        echo -e "${RED}❌ Service Down${NC}"
        return 1
    else
        echo -e "${GREEN}✅ Service Healthy${NC}"
        return 0
    fi
}

# Function to get metrics
get_metrics() {
    local metrics=$(curl -s --connect-timeout 2 --max-time 2 "$SERVICE_URL/internal/metrics" 2>/dev/null || echo "{}")
    echo "$metrics"
}

# Function to parse and display metrics
display_metrics() {
    local metrics="$1"
    
    if [ "$metrics" = "{}" ] || [ -z "$metrics" ]; then
        echo -e "${YELLOW}⚠️  No metrics available${NC}"
        return
    fi
    
    echo -e "\n${WHITE}📊 SERVICE METRICS${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
    
    # Parse and display each metric
    echo "$metrics" | jq -r 'to_entries[] | "\(.key): \(.value | to_entries[] | "\(.key): \(.value)")"' 2>/dev/null | while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo -e "${CYAN}$line${NC}"
        fi
    done
}

# Function to get performance stats
get_performance() {
    echo -e "\n${WHITE}⚡ PERFORMANCE TEST${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
    
    # Quick performance test
    local payload_file="/tmp/dashboard_test.json"
    echo '{"token":"dashboard-test-token"}' > "$payload_file"
    
    local result=$(ab -n 20 -c 5 -H "Content-Type: application/json" -p "$payload_file" -q "$SERVICE_URL/internal/auth/validate-token" 2>/dev/null || echo "FAILED")
    rm -f "$payload_file"
    
    if [ "$result" = "FAILED" ]; then
        echo -e "${RED}❌ Performance test failed${NC}"
    else
        local rps=$(echo "$result" | grep "Requests per second" | awk '{print $4}' | cut -d'[' -f1)
        local p50=$(echo "$result" | grep "50%" | awk '{print $2}')
        local p95=$(echo "$result" | grep "95%" | awk '{print $2}')
        local p99=$(echo "$result" | grep "99%" | awk '{print $2}')
        
        echo -e "${GREEN}📈 Throughput: ${rps} RPS${NC}"
        echo -e "${GREEN}📊 P50 Latency: ${p50}ms${NC}"
        echo -e "${GREEN}📊 P95 Latency: ${p95}ms${NC}"
        echo -e "${GREEN}📊 P99 Latency: ${p99}ms${NC}"
        
        # Performance assessment
        if [ -n "$p95" ] && [ "$p95" -lt 50 ]; then
            echo -e "${GREEN}✅ Performance: EXCELLENT (P95 < 50ms)${NC}"
        elif [ -n "$p95" ] && [ "$p95" -lt 100 ]; then
            echo -e "${YELLOW}⚠️  Performance: GOOD (P95 < 100ms)${NC}"
        else
            echo -e "${RED}❌ Performance: NEEDS IMPROVEMENT (P95 > 100ms)${NC}"
        fi
    fi
}

# Function to get system info
get_system_info() {
    echo -e "\n${WHITE}🖥️  SYSTEM INFO${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    echo -e "${CYAN}CPU Usage: ${cpu_usage}%${NC}"
    
    # Memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
    echo -e "${CYAN}Memory Usage: ${mem_usage}%${NC}"
    
    # Docker containers
    local containers=$(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "(cqos|postgres|redis)" || echo "No containers found")
    echo -e "${CYAN}Containers:${NC}"
    echo "$containers" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo -e "${CYAN}  $line${NC}"
        fi
    done
}

# Function to show optimization status
get_optimization_status() {
    echo -e "\n${WHITE}🚀 OPTIMIZATION STATUS${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
    
    # Check if service is optimized
    local logs=$(docker logs cqos-user-service --tail 5 2>/dev/null | grep "thread_pool" || echo "")
    if [ -n "$logs" ]; then
        local thread_pool=$(echo "$logs" | grep -o 'thread_pool":"[^"]*' | cut -d'"' -f3)
        echo -e "${GREEN}✅ Thread Pool: ${thread_pool}${NC}"
    else
        echo -e "${YELLOW}⚠️  Thread Pool: Unknown${NC}"
    fi
    
    # Check database connections
    local db_connections=$(docker exec cqos-postgres psql -U cqos_user -d cqos_db -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | tr -d ' ' || echo "N/A")
    echo -e "${GREEN}✅ DB Connections: ${db_connections}${NC}"
    
    # Check Redis status
    local redis_status=$(docker exec cqos-redis redis-cli ping 2>/dev/null || echo "FAILED")
    if [ "$redis_status" = "PONG" ]; then
        echo -e "${GREEN}✅ Redis: Connected${NC}"
    else
        echo -e "${RED}❌ Redis: Disconnected${NC}"
    fi
}

# Main dashboard loop
main() {
    while true; do
        clear_screen
        
        # Check if service is running
        if ! get_health; then
            echo -e "\n${RED}❌ Service is not running. Please start with: make docker-run${NC}"
            echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
            sleep $REFRESH_INTERVAL
            continue
        fi
        
        # Get and display metrics
        local metrics=$(get_metrics)
        display_metrics "$metrics"
        
        # Get performance stats
        get_performance
        
        # Get system info
        get_system_info
        
        # Get optimization status
        get_optimization_status
        
        # Footer
        echo -e "\n${BLUE}=============================================================================${NC}"
        echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
        echo -e "${CYAN}Refreshing in ${REFRESH_INTERVAL} seconds...${NC}"
        
        sleep $REFRESH_INTERVAL
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}👋 Dashboard stopped. Goodbye!${NC}"; exit 0' INT

# Check dependencies
if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ curl is required but not installed${NC}"
    exit 1
fi

if ! command -v ab &> /dev/null; then
    echo -e "${RED}❌ ApacheBench (ab) is required but not installed${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq is recommended for better metrics parsing${NC}"
fi

# Start dashboard
main

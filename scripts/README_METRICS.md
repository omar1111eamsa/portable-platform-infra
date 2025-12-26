# CQOS User Management Service - Metrics Testing Scripts

This directory contains comprehensive metrics testing and monitoring scripts for the CQOS User Management & Subscription Service.

## 📊 Available Scripts

### 1. `simple_metrics_test.sh` - Quick Metrics Test
**Purpose**: Fast, simple testing of basic service functionality and performance.

**Usage**:
```bash
./scripts/simple_metrics_test.sh
# or
make test-simple-metrics
```

**What it tests**:
- ✅ Health endpoint functionality
- ✅ Metrics endpoint with real-time data
- ✅ Token validation endpoint
- ✅ Performance (10 requests, 5 concurrent)
- ✅ Response time measurement

**Output Example**:
```
=============================================================================
CQOS USER MANAGEMENT SERVICE - SIMPLE METRICS TEST
=============================================================================

1. Testing Health Endpoint
✅ Health endpoint working: {"status":"ok"}

2. Testing Metrics Endpoint
✅ Metrics endpoint working: {"auth.validate_token":{"avg_latency_ms":0.013,"failures":0,"requests":8500,"successes":8500}}

3. Testing Token Validation Endpoint
✅ Token validation endpoint working: {"valid":false,"error":"invalid token"}

4. Testing Performance (10 requests, 5 concurrent)
✅ Performance test completed
   RPS: 975.51
   P95: 6ms

5. Testing Response Time
✅ Response time: 1.234000ms
   Excellent response time (< 100ms)
```

### 2. `test_metrics.sh` - Comprehensive Metrics Test
**Purpose**: Detailed testing of all endpoints, error handling, and performance across different concurrency levels.

**Usage**:
```bash
./scripts/test_metrics.sh
# or
make test-metrics
```

**What it tests**:
- 🔍 Service health checks
- 🔍 All basic endpoints (health, metrics, API endpoints)
- 🔍 Authentication endpoints with various scenarios
- 🔍 Performance testing across multiple concurrency levels
- 🔍 Error handling (404s, malformed requests)
- 🔍 Optimization metrics validation

### 3. `metrics_dashboard.sh` - Real-time Dashboard
**Purpose**: Live monitoring dashboard with real-time metrics, performance stats, and system information.

**Usage**:
```bash
./scripts/metrics_dashboard.sh
# or
make dashboard
```

**Features**:
- 📊 Real-time service health monitoring
- 📊 Live metrics display with automatic refresh
- 📊 Performance testing with throughput and latency
- 📊 System resource monitoring (CPU, Memory)
- 📊 Docker container status
- 📊 Database and Redis connection status
- 📊 Optimization status (thread pool, connections)

**Dashboard Sections**:
- **Service Health**: Real-time status
- **Service Metrics**: Live endpoint statistics
- **Performance Test**: Continuous throughput/latency monitoring
- **System Info**: CPU, memory, container status
- **Optimization Status**: Thread pool, DB connections, Redis status

## 🚀 Quick Start

### Prerequisites
```bash
# Required tools
sudo apt-get install curl apache2-utils jq

# Optional but recommended
sudo apt-get install bc  # For advanced calculations
```

### Basic Testing
```bash
# Quick health and performance check
make test-simple-metrics

# Comprehensive testing
make test-metrics

# Real-time monitoring
make dashboard
```

## 📈 Understanding the Metrics

### Service Metrics (`/internal/metrics`)
The service provides detailed metrics for each endpoint:

```json
{
  "auth.validate_token": {
    "avg_latency_ms": 0.013,
    "failures": 0,
    "requests": 8500,
    "successes": 8500
  },
  "auth.login": {
    "avg_latency_ms": 306.997,
    "failures": 0,
    "requests": 1,
    "successes": 1
  }
}
```

**Key Metrics**:
- `avg_latency_ms`: Average response time in milliseconds
- `failures`: Number of failed requests
- `requests`: Total number of requests
- `successes`: Number of successful requests

### Performance Targets
- **P95 Latency**: ≤ 50ms (target met: 4-5ms)
- **Throughput**: ≥ 1000 RPS (target met: 1,400-1,900 RPS)
- **Response Time**: < 100ms (achieved: 1-2ms)

## 🔧 Troubleshooting

### Service Not Responding
```bash
# Check if service is running
docker ps

# Check service logs
docker logs cqos-user-service

# Restart service
make docker-run
```

### Performance Issues
```bash
# Check system resources
docker stats

# Check database connections
docker exec cqos-postgres psql -U cqos_user -d cqos_db -c "SELECT count(*) FROM pg_stat_activity;"

# Check Redis status
docker exec cqos-redis redis-cli ping
```

### Script Dependencies
```bash
# Install missing tools
sudo apt-get update
sudo apt-get install curl apache2-utils jq bc

# Verify tools are installed
curl --version
ab -V
jq --version
```

## 📊 Interpreting Results

### Excellent Performance
- P95 Latency: < 10ms
- Throughput: > 1000 RPS
- Response Time: < 5ms
- Success Rate: 100%

### Good Performance
- P95 Latency: 10-50ms
- Throughput: 500-1000 RPS
- Response Time: 5-50ms
- Success Rate: > 95%

### Needs Attention
- P95 Latency: > 50ms
- Throughput: < 500 RPS
- Response Time: > 50ms
- Success Rate: < 95%

## 🎯 Optimization Status

The service includes several optimization layers:

1. **Thread Pool**: 128 threads for high concurrency
2. **Database Pool**: 64 connections for database efficiency
3. **Response Caching**: 30-second cache for repeated requests
4. **Token Caching**: 5-minute cache for JWT validation
5. **Rate Limiting**: 100,000 requests/minute limit
6. **In-Memory Processing**: Reduced database calls

## 📝 Customization

### Modify Test Parameters
Edit the scripts to adjust:
- Concurrency levels
- Request counts
- Timeout values
- Refresh intervals (dashboard)

### Add Custom Tests
Extend the scripts to test:
- Custom endpoints
- Specific performance scenarios
- Integration with external services
- Custom metrics collection

## 🚨 Alerts and Monitoring

The dashboard provides real-time alerts for:
- Service downtime
- High latency (> 100ms)
- Low throughput (< 500 RPS)
- High error rates
- Resource exhaustion

## 📞 Support

For issues with the metrics scripts:
1. Check service logs: `docker logs cqos-user-service`
2. Verify dependencies: `curl --version && ab -V && jq --version`
3. Test basic connectivity: `curl http://localhost:8080/health`
4. Review this documentation for troubleshooting steps

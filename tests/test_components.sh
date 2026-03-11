#!/bin/bash
# Script: test_components.sh
# Purpose: Verify that ClickHouse, Prometheus, and Grafana are running correctly
# Usage: ./test_components.sh
# Author: NetFlow Analytics Team
# Date: 2026-03-10

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"
PROMETHEUS_HOST="${PROMETHEUS_HOST:-localhost}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_HOST="${GRAFANA_HOST:-localhost}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
TIMEOUT=5

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Print functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
    ((TESTS_RUN++))
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Test functions
test_clickhouse_http() {
    print_test "Testing ClickHouse HTTP interface..."
    if curl -s --max-time $TIMEOUT "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_HTTP_PORT}/ping" | grep -q "Ok"; then
        print_success "ClickHouse HTTP interface is responding"
        return 0
    else
        print_failure "ClickHouse HTTP interface is not responding"
        return 1
    fi
}

test_clickhouse_version() {
    print_test "Testing ClickHouse version query..."
    VERSION=$(curl -s --max-time $TIMEOUT "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_HTTP_PORT}/?query=SELECT+version()" 2>/dev/null)
    if [ -n "$VERSION" ]; then
        print_success "ClickHouse version: $VERSION"
        return 0
    else
        print_failure "Could not retrieve ClickHouse version"
        return 1
    fi
}

test_clickhouse_query() {
    print_test "Testing ClickHouse query execution..."
    RESULT=$(curl -s --max-time $TIMEOUT "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_HTTP_PORT}/?query=SELECT+1+as+test" 2>/dev/null)
    if [ "$RESULT" = "1" ]; then
        print_success "ClickHouse query execution successful"
        return 0
    else
        print_failure "ClickHouse query execution failed: $RESULT"
        return 1
    fi
}

test_clickhouse_databases() {
    print_test "Testing ClickHouse database access..."
    DATABASES=$(curl -s --max-time $TIMEOUT "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_HTTP_PORT}/?query=SHOW+DATABASES+FORMAT+TabSeparated" 2>/dev/null)
    if [ -n "$DATABASES" ]; then
        print_success "ClickHouse databases accessible"
        print_info "Available databases:"
        echo "$DATABASES" | sed 's/^/  - /'
        return 0
    else
        print_failure "Could not list ClickHouse databases"
        return 1
    fi
}

test_prometheus_health() {
    print_test "Testing Prometheus health endpoint..."
    if curl -s --max-time $TIMEOUT "http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}/-/healthy" | grep -q "Prometheus is Healthy"; then
        print_success "Prometheus is healthy"
        return 0
    else
        print_failure "Prometheus health check failed"
        return 1
    fi
}

test_prometheus_ready() {
    print_test "Testing Prometheus readiness..."
    if curl -s --max-time $TIMEOUT "http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}/-/ready" | grep -q "Prometheus is Ready"; then
        print_success "Prometheus is ready"
        return 0
    else
        print_failure "Prometheus readiness check failed"
        return 1
    fi
}

test_prometheus_targets() {
    print_test "Testing Prometheus targets..."
    TARGETS=$(curl -s --max-time $TIMEOUT "http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}/api/v1/targets" 2>/dev/null)
    if echo "$TARGETS" | grep -q '"status":"success"'; then
        print_success "Prometheus targets endpoint accessible"
        ACTIVE_TARGETS=$(echo "$TARGETS" | grep -o '"health":"up"' | wc -l)
        print_info "Active targets: $ACTIVE_TARGETS"
        return 0
    else
        print_failure "Could not retrieve Prometheus targets"
        return 1
    fi
}

test_grafana_health() {
    print_test "Testing Grafana health endpoint..."
    HEALTH=$(curl -s --max-time $TIMEOUT "http://${GRAFANA_HOST}:${GRAFANA_PORT}/api/health" 2>/dev/null)
    if echo "$HEALTH" | grep -q '"database":"ok"'; then
        print_success "Grafana is healthy"
        return 0
    else
        print_failure "Grafana health check failed"
        return 1
    fi
}

test_grafana_datasources() {
    print_test "Testing Grafana datasources..."
    # Note: This requires authentication, so we'll just test if the endpoint responds
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "http://${GRAFANA_HOST}:${GRAFANA_PORT}/api/datasources" 2>/dev/null)
    if [ "$STATUS" = "401" ] || [ "$STATUS" = "200" ]; then
        print_success "Grafana API is accessible (status: $STATUS)"
        print_info "Use admin credentials to check datasources in UI"
        return 0
    else
        print_failure "Grafana API not accessible (status: $STATUS)"
        return 1
    fi
}

test_docker_containers() {
    print_test "Testing Docker container status..."
    if ! command -v docker &> /dev/null; then
        print_failure "Docker command not found"
        return 1
    fi
    
    CONTAINERS=("clickhouse01" "prometheus" "grafana")
    ALL_RUNNING=true
    
    for container in "${CONTAINERS[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            STATUS=$(docker ps --filter "name=${container}" --format '{{.Status}}')
            print_info "$container: $STATUS"
        else
            print_failure "$container is not running"
            ALL_RUNNING=false
        fi
    done
    
    if [ "$ALL_RUNNING" = true ]; then
        print_success "All containers are running"
        return 0
    else
        return 1
    fi
}

test_network_connectivity() {
    print_test "Testing network connectivity between containers..."
    if ! command -v docker &> /dev/null; then
        print_failure "Docker command not found"
        return 1
    fi
    
    # Test if Prometheus can reach ClickHouse
    PROM_TO_CH=$(docker exec prometheus wget -q -O- --timeout=$TIMEOUT http://clickhouse01:8123/ping 2>/dev/null || echo "failed")
    if [ "$PROM_TO_CH" = "Ok." ]; then
        print_success "Prometheus can reach ClickHouse"
    else
        print_failure "Prometheus cannot reach ClickHouse"
        return 1
    fi
    
    # Test if Grafana can reach ClickHouse
    GRAFANA_TO_CH=$(docker exec grafana wget -q -O- --timeout=$TIMEOUT http://clickhouse01:8123/ping 2>/dev/null || echo "failed")
    if [ "$GRAFANA_TO_CH" = "Ok." ]; then
        print_success "Grafana can reach ClickHouse"
    else
        print_failure "Grafana cannot reach ClickHouse"
        return 1
    fi
    
    # Test if Grafana can reach Prometheus
    GRAFANA_TO_PROM=$(docker exec grafana wget -q -O- --timeout=$TIMEOUT http://prometheus:9090/-/healthy 2>/dev/null || echo "failed")
    if echo "$GRAFANA_TO_PROM" | grep -q "Prometheus is Healthy"; then
        print_success "Grafana can reach Prometheus"
    else
        print_failure "Grafana cannot reach Prometheus"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    print_header "NetFlow Analytics - Component Testing"
    echo ""
    
    print_header "1. Docker Container Status"
    test_docker_containers || true
    echo ""
    
    print_header "2. ClickHouse Tests"
    test_clickhouse_http || true
    test_clickhouse_version || true
    test_clickhouse_query || true
    test_clickhouse_databases || true
    echo ""
    
    print_header "3. Prometheus Tests"
    test_prometheus_health || true
    test_prometheus_ready || true
    test_prometheus_targets || true
    echo ""
    
    print_header "4. Grafana Tests"
    test_grafana_health || true
    test_grafana_datasources || true
    echo ""
    
    print_header "5. Network Connectivity Tests"
    test_network_connectivity || true
    echo ""
    
    print_header "Test Results Summary"
    echo -e "Tests Run:    ${BLUE}${TESTS_RUN}${NC}"
    echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed! ✓"
        echo ""
        print_info "Access URLs:"
        echo "  - ClickHouse: http://${CLICKHOUSE_HOST}:${CLICKHOUSE_HTTP_PORT}/play"
        echo "  - Prometheus: http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}"
        echo "  - Grafana:    http://${GRAFANA_HOST}:${GRAFANA_PORT} (admin/admin_change_me)"
        exit 0
    else
        print_failure "Some tests failed!"
        echo ""
        print_info "Troubleshooting steps:"
        echo "  1. Check if all containers are running: docker ps"
        echo "  2. Check container logs: docker logs <container_name>"
        echo "  3. Verify .env configuration in docker/.env"
        echo "  4. Try restarting: docker-compose down && docker-compose up -d"
        exit 1
    fi
}

# Run main function
main

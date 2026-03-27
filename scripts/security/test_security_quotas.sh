#!/bin/bash
# filepath: scripts/security/test_security_quotas.sh
# Purpose: Test ClickHouse query quotas and resource limits
# Style: Show raw command output and provide manual checks
# Usage: ./scripts/security/test_security_quotas.sh

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CLICKHOUSE_NODE="clickhouse01"
DB="netflow"
TABLE="flows_replicated"
ADMIN_PASSWORD="${CLICKHOUSE_PASSWORD:-admin}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ClickHouse Query Quota Testing${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to execute query as admin
query_admin() {
    local query=$1
    docker exec "$CLICKHOUSE_NODE" clickhouse-client --password="$ADMIN_PASSWORD" --query="$query" 2>&1
}

# Function to execute query as specific user
query_as_user() {
    local user=$1
    local password=$2
    local query=$3
    docker exec "$CLICKHOUSE_NODE" clickhouse-client --user="$user" --password="$password" --query="$query" 2>&1
}

print_check() {
    local message=$1
    echo -e "${CYAN}Check:${NC} $message"
}

# Step 1: Check current quotas
echo -e "${YELLOW}Step 1: List Current Quotas${NC}"
echo "Quota metadata:"
query_admin "
    SELECT
        name,
        keys,
        durations,
        apply_to_all,
        apply_to_list,
        apply_to_except
    FROM system.quotas
    FORMAT Vertical
" || true
echo ""
echo "Quota limits:"
query_admin "
    SELECT
        quota_name,
        duration,
        max_queries,
        max_errors,
        max_result_rows,
        max_result_bytes,
        max_read_rows,
        max_read_bytes,
        max_execution_time,
        max_written_bytes
    FROM system.quota_limits
    ORDER BY quota_name, duration
    FORMAT Vertical
" || true
print_check "Quota metadata and limit rows should list successfully. Empty results mean no SQL-defined quotas are currently configured."
echo ""

# Step 2: Create Test Users
echo -e "${YELLOW}Step 2: Create Test Users${NC}"
query_admin "DROP USER IF EXISTS limited_user"
query_admin "DROP USER IF EXISTS heavy_user"
query_admin "CREATE USER limited_user IDENTIFIED BY 'limited_password'"
query_admin "CREATE USER heavy_user IDENTIFIED BY 'heavy_password'"
query_admin "GRANT SELECT ON $DB.$TABLE TO limited_user"
query_admin "GRANT SELECT ON $DB.$TABLE TO heavy_user"

# Step 3: Create basic query quota
echo -e "${YELLOW}Step 3: Create Basic Query Quota${NC}"
query_admin "DROP QUOTA IF EXISTS basic_quota"
query_admin "
    CREATE QUOTA basic_quota
    FOR INTERVAL 1 minute MAX queries = 10
    TO limited_user
"
print_check "No error should be returned while creating basic_quota."
echo ""

# Step 4: Create resource-based quota
echo -e "${YELLOW}Step 4: Create Resource-Based Quota${NC}"
query_admin "DROP QUOTA IF EXISTS resource_quota"
query_admin "
    CREATE QUOTA resource_quota
    FOR INTERVAL 1 minute
        MAX queries = 20,
        MAX result_rows = 100000,
        MAX read_rows = 500000,
        MAX execution_time = 30
    TO heavy_user
"

echo "User grants:"
query_admin "SHOW GRANTS FOR limited_user"
query_admin "SHOW GRANTS FOR heavy_user"
print_check "Each user should exist and show SELECT access on the target table."
echo ""

print_check "No error should be returned while creating resource_quota."
echo ""

# Step 5: Verify quota configuration
echo -e "${YELLOW}Step 5: Verify Quota Configuration${NC}"
echo "Configured quota metadata:"
query_admin "
    SELECT
        name,
        keys,
        durations,
        apply_to_all,
        apply_to_list,
        apply_to_except
    FROM system.quotas
    ORDER BY name
    FORMAT Vertical
"
echo ""
echo "Configured quota limits:"
query_admin "
    SELECT
        quota_name,
        duration,
        max_queries,
        max_result_rows,
        max_read_rows,
        max_execution_time
    FROM system.quota_limits
    WHERE quota_name IN ('basic_quota', 'resource_quota')
    ORDER BY quota_name, duration
    FORMAT Vertical
"
print_check "basic_quota and resource_quota should appear in system.quotas, and their per-interval limits should appear in system.quota_limits."
echo ""

# Step 6: Test query limit enforcement
echo -e "${YELLOW}Step 6: Test Query Limit Enforcement${NC}"
echo "Running 15 queries as limited_user (quota is 10 queries/minute)..."
echo ""
for i in {1..15}; do
    echo "Query $i:"
    query_as_user "limited_user" "limited_password" "SELECT count() FROM $DB.$TABLE LIMIT 1" || true
    sleep 0.1
done
print_check "Early queries should succeed. Once the limit is reached, output should contain QUOTA_EXCEEDED."
echo ""

# Step 7: Monitor quota usage
echo -e "${YELLOW}Step 7: Monitor Quota Usage${NC}"
echo "Current quota usage for limited_user:"
query_admin "
    SELECT
        quota_name,
        quota_key,
        is_current,
        duration,
        queries,
        max_queries,
        query_selects,
        max_query_selects,
        errors,
        max_errors
    FROM system.quotas_usage
    WHERE quota_name = 'basic_quota'
    FORMAT Vertical
" || true
print_check "Usage rows should show current consumption for basic_quota after running the previous queries."
echo ""

# Step 8: Test result row limit
echo -e "${YELLOW}Step 8: Test Result Row Limit${NC}"
echo "Current row count in the target table:"
query_admin "SELECT count() FROM $DB.$TABLE"
echo ""
echo "Attempting a large result-set query as heavy_user:"
query_as_user "heavy_user" "heavy_password" "SELECT * FROM $DB.$TABLE LIMIT 100001 FORMAT Null" || true
print_check "If the table has more than 100,000 rows, output should eventually contain QUOTA_EXCEEDED or a resource limit error. If it does not, the table may not be large enough to trigger the limit."
echo ""

# Step 9: Show quota details
echo -e "${YELLOW}Step 9: Detailed Quota Analysis${NC}"
echo "Quota limits summary:"
query_admin "
    SELECT
        q.name as quota_name,
        q.keys as applies_to,
        l.duration as interval_sec,
        l.max_queries,
        l.max_result_rows,
        l.max_read_rows,
        l.max_execution_time as max_exec_time_sec
    FROM system.quotas AS q
    LEFT JOIN system.quota_limits AS l ON q.name = l.quota_name
    WHERE q.name IN ('basic_quota', 'resource_quota')
    ORDER BY q.name, l.duration
    FORMAT PrettyCompact
"
print_check "The summary should match the intended quota values for both quotas."
echo ""

# Step 10: Test quota reset after interval
echo -e "${YELLOW}Step 10: Quota Reset Demonstration${NC}"
echo "Quota usage snapshot before waiting:"
query_admin "
    SELECT
        quota_name,
        quota_key,
        is_current,
        duration,
        queries,
        max_queries
    FROM system.quotas_usage
    WHERE quota_name = 'basic_quota'
    FORMAT Vertical
" || true
echo ""
echo "Waiting 5 seconds..."
sleep 5
echo ""
echo "Quota usage snapshot after waiting:"
query_admin "
    SELECT
        quota_name,
        quota_key,
        is_current,
        duration,
        queries,
        max_queries
    FROM system.quotas_usage
    WHERE quota_name = 'basic_quota'
    FORMAT Vertical
" || true
print_check "Usage may change over time, but full reset for basic_quota only happens after its 60-second interval."
echo ""

# Step 11: View quota usage across all users
echo -e "${YELLOW}Step 11: System-Wide Quota Usage${NC}"
echo "Quota usage for all users:"
query_admin "
    SELECT
        quota_name,
        quota_key,
        is_current,
        duration,
        queries,
        max_queries,
        errors,
        max_errors
    FROM system.quotas_usage
    ORDER BY quota_name, quota_key, duration
    FORMAT PrettyCompact
" || true
print_check "Usage rows should show activity for limited_user and heavy_user if previous steps were executed."
echo ""

# Step 12: Cleanup
echo -e "${YELLOW}Step 12: Cleanup: Remove test users and quotas${NC}"

query_admin "DROP QUOTA IF EXISTS basic_quota"
query_admin "DROP QUOTA IF EXISTS resource_quota"
query_admin "DROP USER IF EXISTS limited_user"
query_admin "DROP USER IF EXISTS heavy_user"
print_check "Cleanup should complete without errors."

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Query Quota Testing Complete${NC}"
echo -e "${BLUE}========================================${NC}"
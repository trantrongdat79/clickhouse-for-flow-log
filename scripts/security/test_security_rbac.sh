#!/bin/bash
# filepath: scripts/security/test_security_rbac.sh
# Purpose: Test ClickHouse Role-Based Access Control (RBAC)
# Style: Show raw command output and provide manual checks
# Usage: ./scripts/security/test_security_rbac.sh

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
echo -e "${BLUE}ClickHouse RBAC Security Testing${NC}"
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

# Test 1: Check current users and roles
echo -e "${YELLOW}Test 1: List Current Users and Roles${NC}"
echo "Current users:"
query_admin "SELECT name, host_ip, host_names FROM system.users FORMAT PrettyCompact"
echo "Current roles:"
query_admin "SELECT name FROM system.roles FORMAT PrettyCompact" || true
print_check "Users and roles should list successfully."
echo ""

# Test 2: Create analyst role (read-only access)
echo -e "${YELLOW}Test 2: Create Analyst Role (Read-Only)${NC}"
query_admin "DROP ROLE IF EXISTS analyst"
query_admin "CREATE ROLE analyst"
query_admin "GRANT SELECT ON $DB.* TO analyst"
print_check "No errors while creating role 'analyst' and granting SELECT."
echo ""

# Test 3: Create engineer role (read-write access)
echo -e "${YELLOW}Test 3: Create Engineer Role (Read-Write)${NC}"
query_admin "DROP ROLE IF EXISTS engineer"
query_admin "CREATE ROLE engineer"
query_admin "GRANT SELECT, INSERT ON $DB.* TO engineer"
print_check "No errors while creating role 'engineer' and granting SELECT, INSERT."
echo ""

# Test 4: Create admin role (full access)
echo -e "${YELLOW}Test 4: Create DBA Role (Full Access)${NC}"
query_admin "DROP ROLE IF EXISTS dba"
query_admin "CREATE ROLE dba"
query_admin "GRANT ALL ON $DB.* TO dba"
query_admin "GRANT CREATE DATABASE, CREATE TABLE ON *.* TO dba"
print_check "No errors while creating role 'dba' and granting broad privileges."
echo ""

# Test 5: Create test users
echo -e "${YELLOW}Test 5: Create Test Users${NC}"
query_admin "DROP USER IF EXISTS alice"
query_admin "CREATE USER alice IDENTIFIED BY 'alice_password'"
query_admin "GRANT analyst TO alice"

query_admin "DROP USER IF EXISTS bob"
query_admin "CREATE USER bob IDENTIFIED BY 'bob_password'"
query_admin "GRANT engineer TO bob"

query_admin "DROP USER IF EXISTS charlie"
query_admin "CREATE USER charlie IDENTIFIED BY 'charlie_password'"
query_admin "GRANT dba TO charlie"

echo "User permissions summary:"
query_admin "SHOW GRANTS FOR alice"
query_admin "SHOW GRANTS FOR bob"
query_admin "SHOW GRANTS FOR charlie"
print_check "Each user should show the expected granted role."
echo ""

# Test 6: Test read access (alice - analyst)
echo -e "${YELLOW}Test 6: Test Read-Only Access (Alice)${NC}"
echo "Alice (analyst) SELECT:"
query_as_user "alice" "alice_password" "SELECT count() FROM $DB.$TABLE"
print_check "Output should be a numeric row count."
echo ""

echo "Alice (analyst) INSERT (expected deny):"
query_as_user "alice" "alice_password" "INSERT INTO $DB.$TABLE (timestamp, src_ip, src_port, dst_ip, dst_port, protocol, bytes, packets, flow_duration, src_geo_latitude, src_geo_longitude, dst_geo_latitude, dst_geo_longitude, tcp_flags) VALUES (now(), '192.168.1.1', 1111, '10.0.0.1', 80, 6, 100, 10, 5, 0, 0, 0, 0, 2)" || true
print_check "Output should contain ACCESS_DENIED or Not enough privileges."
echo ""

# Test 7: Test read-write access (bob - engineer)
echo -e "${YELLOW}Test 7: Test Read-Write Access (Bob)${NC}"
echo "Bob (engineer) INSERT:"
query_as_user "bob" "bob_password" "INSERT INTO $DB.$TABLE (timestamp, src_ip, src_port, dst_ip, dst_port, protocol, bytes, packets, flow_duration, src_geo_latitude, src_geo_longitude, dst_geo_latitude, dst_geo_longitude, tcp_flags) VALUES (now(), '192.168.1.2', 2222, '10.0.0.2', 443, 6, 200, 20, 10, 0, 0, 0, 0, 2)"
print_check "Should return no error for INSERT."
echo ""

echo "Bob (engineer) DROP TABLE (expected deny):"
query_as_user "bob" "bob_password" "DROP TABLE $DB.$TABLE" || true
print_check "Output should contain ACCESS_DENIED or Not enough privileges."
echo ""

# Test 8: Test full access (charlie - dba)
echo -e "${YELLOW}Test 8: Test Full Access (Charlie - DBA)${NC}"
echo "Charlie (DBA) CREATE TABLE:"
query_as_user "charlie" "charlie_password" "CREATE TABLE IF NOT EXISTS $DB.test_rbac (id UInt32, name String) ENGINE = MergeTree() ORDER BY id"
print_check "Should return no error for CREATE TABLE."

echo "Charlie (DBA) DROP TABLE:"
query_as_user "charlie" "charlie_password" "DROP TABLE IF EXISTS $DB.test_rbac"
print_check "Should return no error for DROP TABLE."
echo ""

# Test 9: Test role hierarchy
echo -e "${YELLOW}Test 9: Test Role Inheritance${NC}"
query_admin "DROP ROLE IF EXISTS senior_analyst"
query_admin "CREATE ROLE senior_analyst"
query_admin "GRANT analyst TO senior_analyst"
query_admin "GRANT INSERT ON $DB.$TABLE TO senior_analyst"

query_admin "DROP USER IF EXISTS david"
query_admin "CREATE USER david IDENTIFIED BY 'david_password'"
query_admin "GRANT senior_analyst TO david"

echo "David (senior_analyst) INSERT:"
query_as_user "david" "david_password" "INSERT INTO $DB.$TABLE (timestamp, src_ip, src_port, dst_ip, dst_port, protocol, bytes, packets, flow_duration, src_geo_latitude, src_geo_longitude, dst_geo_latitude, dst_geo_longitude, tcp_flags) VALUES (now(), '192.168.1.3', 3333, '10.0.0.3', 22, 6, 300, 30, 15, 0, 0, 0, 0, 2)"
print_check "Should return no error for INSERT if inheritance works."
echo ""

# Test 10: Test network restrictions
echo -e "${YELLOW}Test 10: Network-Based Access Control${NC}"
query_admin "DROP USER IF EXISTS eve"
query_admin "CREATE USER eve IDENTIFIED BY 'eve_password' HOST IP '192.168.1.100'"
query_admin "GRANT SELECT ON $DB.* TO eve"
print_check "User creation should succeed; host restriction should appear in system.users host_ip."
echo ""

# Test 11: Display complete RBAC configuration
echo -e "${YELLOW}Test 11: RBAC Configuration Summary${NC}"
echo "All users:"
query_admin "SELECT name, storage, host_ip, host_names FROM system.users FORMAT PrettyCompact"
echo "All roles:"
query_admin "SELECT name FROM system.roles FORMAT PrettyCompact"
echo "Role grants:"
query_admin "SELECT user_name, role_name, granted_role_name FROM system.role_grants FORMAT PrettyCompact" || true
echo "Detailed grants:"
query_admin "SELECT user_name, role_name, access_type, database, table, is_partial_revoke FROM system.grants ORDER BY user_name, database, table FORMAT PrettyCompact"
print_check "Review grants and host restrictions match intended policy."
echo ""

# Test 12: Cleanup
echo -e "${YELLOW}Test 12: Cleanup Remove test users and roles${NC}"
query_admin "DROP USER IF EXISTS alice"
query_admin "DROP USER IF EXISTS bob"
query_admin "DROP USER IF EXISTS charlie"
query_admin "DROP USER IF EXISTS david"
query_admin "DROP USER IF EXISTS eve"
query_admin "DROP ROLE IF EXISTS analyst"
query_admin "DROP ROLE IF EXISTS engineer"
query_admin "DROP ROLE IF EXISTS dba"
query_admin "DROP ROLE IF EXISTS senior_analyst"
print_check "All temporary users and roles should be removed without errors."
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RBAC Testing Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Mode:${NC} Raw output shown. Use each Check note to validate expected behavior."

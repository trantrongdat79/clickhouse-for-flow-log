#!/bin/bash
# Script: 01-init-schema.sh
# Purpose: Initialize ClickHouse database schema for NetFlow analytics
# Usage: ./01-init-schema.sh
# Author: NetFlow Analytics Team
# Date: 2026-03-16

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../../sql/schema"
CH_CONTAINER="clickhouse01"
CH_PASSWORD="${CLICKHOUSE_PASSWORD:-admin}"
CH_CLIENT="docker exec -i ${CH_CONTAINER} clickhouse-client --password=${CH_PASSWORD}"
INIT_LOG="${SCRIPT_DIR}/.ch_init.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "========================================"
echo "ClickHouse Schema Initialization"
echo "========================================"
echo ""

# Check if ClickHouse container is running
if ! docker ps | grep -q "${CH_CONTAINER}"; then
    echo -e "${RED}ERROR: ClickHouse container '${CH_CONTAINER}' is not running${NC}"
    echo "Please start the cluster first: cd docker && docker compose up -d"
    exit 1
fi

# Wait for ClickHouse to be ready
echo -e "${YELLOW}Waiting for ClickHouse to be ready...${NC}"
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if ${CH_CLIENT} --query "SELECT 1" &> /dev/null; then
        echo -e "${GREEN}✓ ClickHouse is ready${NC}"
        break
    fi
    attempt=$((attempt + 1))
    echo -n "."
    sleep 1
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "${RED}ERROR: ClickHouse did not become ready in time${NC}"
    exit 1
fi

echo ""

# Execute SQL files in order
echo "Executing DDL scripts..."
for sql_file in "${SQL_DIR}"/*.sql; do
    if [ -f "$sql_file" ]; then
        filename=$(basename "$sql_file")
        echo -n "  ${filename}... "
        
        if ${CH_CLIENT} --multiquery < "$sql_file" 2>&1 | tee "$INIT_LOG" | grep -q "Exception"; then
            echo -e "${RED}FAILED${NC}"
            echo "Error details:"
            cat "$INIT_LOG"
            exit 1
        else
            echo -e "${GREEN}✓${NC}"
        fi
    fi
done

rm -f "$INIT_LOG"

echo ""
echo "========================================"
echo "Verifying schema..."
echo "========================================"
echo ""

# Verify table exists
echo "Tables in database:"
${CH_CLIENT} --query "SHOW TABLES FROM netflow" | while read table; do
    echo "  - $table"
done

echo ""

# Show table structure
echo "Structure of netflow.flows_local table:"
${CH_CLIENT} --query "DESCRIBE TABLE netflow.flows_local FORMAT PrettyCompact"

echo ""

# Show table details
echo "Table details:"
${CH_CLIENT} --query "
SELECT 
    engine,
    partition_key,
    sorting_key,
    primary_key
FROM system.tables 
WHERE name = 'flows_local' AND database = 'netflow'
FORMAT Vertical
"

echo ""

# Show indexes
echo "Indexes on netflow.flows_local:"
${CH_CLIENT} --query "
SELECT 
    name,
    type,
    expr
FROM system.data_skipping_indices
WHERE table = 'flows_local' AND database = 'netflow'
FORMAT PrettyCompact
"

echo ""
echo "========================================"
echo -e "${GREEN}✓ Schema initialization complete!${NC}"
echo "========================================"
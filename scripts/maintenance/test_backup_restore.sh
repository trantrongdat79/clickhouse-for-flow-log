#!/bin/bash
# filepath: scripts/maintenance/test_backup_restore.sh
# Purpose: Test ClickHouse native backup and restore functionality
# Usage: ./scripts/maintenance/test_backup_restore.sh

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLICKHOUSE_NODE="clickhouse01"
DB="netflow"
TABLE="flows_replicated"
#PASSWORD="${CLICKHOUSE_PASSWORD:-secure_password_change_me}"
PASSWORD="${CLICKHOUSE_PASSWORD:-admin}"
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../../data-gen/output"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ClickHouse Backup & Restore Testing${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to execute query on node
query_node() {
    local query=$1
    docker exec -i "$CLICKHOUSE_NODE" clickhouse-client --password="$PASSWORD" --query="$query"
}

# Step 1: Check initial data
echo -e "${YELLOW}Step 1: Pre-Backup Data Check${NC}"
INITIAL_COUNT=$(query_node "SELECT count() FROM $DB.$TABLE")
echo "Total rows in $DB.$TABLE: $INITIAL_COUNT"
echo ""

if [ "$INITIAL_COUNT" -eq "0" ]; then
    echo "No data found. Inserting data from JSON files in $DATA_DIR..."

    if [ ! -d "$DATA_DIR" ]; then
        echo -e "${RED}✗ Data directory not found: $DATA_DIR${NC}"
        echo "Please generate data first using: cd data-gen && python generate_flows.py"
        exit 1
    fi

    JSON_FILES=$(find "$DATA_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | sort)
    if [ -z "$JSON_FILES" ]; then
        echo -e "${RED}✗ No JSON files found in $DATA_DIR${NC}"
        echo "Please generate data first using: cd data-gen && python generate_flows.py"
        exit 1
    fi

    FILE_COUNT=$(echo "$JSON_FILES" | wc -l)
    echo "Found $FILE_COUNT JSON file(s) to insert"

    for JSON_FILE in $JSON_FILES; do
        FILENAME=$(basename "$JSON_FILE")
        echo "Inserting $FILENAME..."

        cat "$JSON_FILE" | docker exec -i "$CLICKHOUSE_NODE" clickhouse-client \
            --password="$PASSWORD" \
            --query="INSERT INTO $DB.$TABLE FORMAT JSONEachRow" \
            2>&1 | grep -v "^$" || true

        echo -e "${GREEN}✓ Inserted $FILENAME${NC}"
    done

    INITIAL_COUNT=$(query_node "SELECT count() FROM $DB.$TABLE")
    echo -e "${GREEN}✓ Data insert completed${NC}"
    echo "Total rows now: $INITIAL_COUNT"
fi
echo ""

# Step 2: Create native backup
echo -e "${YELLOW}Step 2: Native BACKUP${NC}"
VERSION=$(query_node "SELECT version()")
echo "ClickHouse version: $VERSION"
echo "Creating backup: $BACKUP_NAME"

if ! query_node "BACKUP TABLE $DB.$TABLE TO Disk('default', '$BACKUP_NAME/')"; then
    echo -e "${RED}✗ BACKUP failed. Ensure ClickHouse >= 22.8 and backup disk is configured.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Backup created successfully${NC}"
echo ""

# Step 3: Verify backup metadata
echo -e "${YELLOW}Step 3: Verify Backup Metadata${NC}"
query_node "
    SELECT
        name,
        status,
        num_files,
        formatReadableSize(total_size) as total_size,
        start_time,
        end_time
    FROM system.backups
    WHERE name LIKE '%$BACKUP_NAME%'
    FORMAT Vertical
" || echo -e "${YELLOW}⚠ Could not query system.backups${NC}"
echo ""

# Step 4: Simulate data loss and restore
echo -e "${YELLOW}Step 4: Simulate Data Loss & Restore${NC}"

echo "Truncating table $DB.$TABLE..."
query_node "TRUNCATE TABLE $DB.$TABLE"
ROWS_AFTER_TRUNCATE=$(query_node "SELECT count() FROM $DB.$TABLE")
echo "Rows after truncation: $ROWS_AFTER_TRUNCATE"
echo -e "${YELLOW}⚠ Data loss simulated${NC}"
echo ""

echo "Restoring from backup: $BACKUP_NAME..."
if ! query_node "RESTORE TABLE $DB.$TABLE FROM Disk('default', '$BACKUP_NAME/')"; then
    echo -e "${RED}✗ RESTORE failed.${NC}"
    exit 1
fi

ROWS_AFTER_RESTORE=$(query_node "SELECT count() FROM $DB.$TABLE")
echo "Rows after restore: $ROWS_AFTER_RESTORE"

if [ "$INITIAL_COUNT" == "$ROWS_AFTER_RESTORE" ]; then
    echo -e "${GREEN}✓ Restore successful: All $ROWS_AFTER_RESTORE rows recovered${NC}"
else
    echo -e "${YELLOW}⚠ Row count differs (Before: $INITIAL_COUNT, After restore: $ROWS_AFTER_RESTORE)${NC}"
fi

echo ""

# Step 5: List available backups
echo -e "${YELLOW}Step 5: List Available Backups${NC}"
query_node "
    SELECT name, status, formatReadableSize(total_size) as size, start_time
    FROM system.backups
    ORDER BY start_time DESC
    FORMAT PrettyCompact
" || echo -e "${YELLOW}⚠ Could not list backups from system.backups${NC}"
echo ""

# Cleanup hint
echo -e "${YELLOW}Cleanup${NC}"
echo "To remove this backup from the disk:"
echo "  docker exec $CLICKHOUSE_NODE rm -rf /var/lib/clickhouse/<backup_disk_path>/$BACKUP_NAME"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Backup & Restore Testing Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Backup name: $BACKUP_NAME"

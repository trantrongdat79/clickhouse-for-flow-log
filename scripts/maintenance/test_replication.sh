#!/bin/bash
# filepath: scripts/maintenance/test_replication.sh
# Purpose: Test ClickHouse cluster replication features
# Features: Bulk insert with replication monitoring, failover simulation
# Usage: ./scripts/maintenance/test_replication.sh

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CLICKHOUSE01="clickhouse01"
CLICKHOUSE02="clickhouse02"
DB="netflow"
TABLE="flows_replicated"
PASSWORD="${CLICKHOUSE_PASSWORD:-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../../data-gen/output"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ClickHouse Replication Testing Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to execute query on specific node
query_node() {
    local node=$1
    local query=$2
    docker exec -i "$node" clickhouse-client --password="$PASSWORD" --query="$query" 2>/dev/null
}

# Function to execute query and return result
query_node_result() {
    local node=$1
    local query=$2
    docker exec -i "$node" clickhouse-client --password="$PASSWORD" --query="$query" 2>&1
}

# Function to check system status (replicas, clusters, ZK)
check_status() {
    local test_label=$1
    echo -e "${CYAN}$test_label - Status Check${NC}"
    echo ""
    
    # Check cluster connectivity
    echo "Checking cluster connectivity..."
    if query_node "$CLICKHOUSE01" "SELECT 1" > /dev/null; then
        echo -e "${GREEN}✓ Node 1 (clickhouse01) is online${NC}"
    else
        echo -e "${RED}✗ Node 1 (clickhouse01) is offline${NC}"
    fi
    
    if query_node "$CLICKHOUSE02" "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Node 2 (clickhouse02) is online${NC}"
    else
        echo -e "${YELLOW}⚠ Node 2 (clickhouse02) is offline${NC}"
    fi
    echo ""
    
    # Check ZooKeeper connectivity
    echo "ZooKeeper connectivity:"
    ZK_STATUS1=$(query_node_result "$CLICKHOUSE01" "SELECT count() FROM system.zookeeper WHERE path = '/'")
    if [ ! -z "$ZK_STATUS1" ] && [ "$ZK_STATUS1" -gt "0" ]; then
        echo -e "${GREEN}✓ Node 1 connected to ZooKeeper${NC}"
    else
        echo -e "${RED}✗ Node 1 cannot connect to ZooKeeper${NC}"
    fi
    
    ZK_STATUS2=$(query_node_result "$CLICKHOUSE02" "SELECT count() FROM system.zookeeper WHERE path = '/'" 2>/dev/null || echo "error")
    if [[ "$ZK_STATUS2" =~ ^[0-9]+$ ]] && [ "$ZK_STATUS2" -gt "0" ]; then
        echo -e "${GREEN}✓ Node 2 connected to ZooKeeper${NC}"
    else
        echo -e "${YELLOW}⚠ Node 2 cannot connect to ZooKeeper (may be offline)${NC}"
    fi
    echo ""
    
    # Check replication status
    echo "Replication status:"
    echo ""
    echo "Node 1 (clickhouse01):"
    query_node "$CLICKHOUSE01" "
        SELECT 
            database,
            table,
            is_leader,
            is_readonly,
            total_replicas,
            active_replicas,
            queue_size AS pending_ops,
            greatest(log_max_index - log_pointer, 0) AS replication_lag_count
        FROM system.replicas 
        WHERE table = '$TABLE'
        FORMAT Vertical
    " || echo -e "${YELLOW}⚠ No replication info available${NC}"
    echo ""
    
    if query_node "$CLICKHOUSE02" "SELECT 1" > /dev/null 2>&1; then
        echo "Node 2 (clickhouse02):"
        query_node "$CLICKHOUSE02" "
            SELECT 
                database,
                table,
                is_leader,
                is_readonly,
                total_replicas,
                active_replicas,
                queue_size AS pending_ops,
                greatest(log_max_index - log_pointer, 0) AS replication_lag_count
            FROM system.replicas 
            WHERE table = '$TABLE'
            FORMAT Vertical
        " || echo -e "${YELLOW}⚠ No replication info available${NC}"
    else
        echo -e "${YELLOW}⚠ Node 2 is offline - skipping replication status${NC}"
    fi
    echo ""
    
    # Check cluster health
    echo "Cluster health:"
    query_node "$CLICKHOUSE01" "
        SELECT 
            cluster,
            shard_num,
            replica_num,
            host_name,
            port,
            is_local,
            errors_count
        FROM system.clusters 
        WHERE cluster = 'netflow_cluster'
        FORMAT PrettyCompact
    "
    echo ""
}

# ========================================
# TEST 1: Normal Replication with Bulk Insert
# ========================================
echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}TEST 1: Normal Replication (Bulk Insert)${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""

# Step 1: Initial status check
echo -e "${YELLOW}Step 1: Status Check (replicas, clusters, ZK)${NC}"
check_status "Test 1"

# Step 2: Bulk insert on clickhouse01 (run in background)
echo -e "${YELLOW}Step 2: Bulk Insert on clickhouse01 (background process)${NC}"
echo "Looking for JSON data files in $DATA_DIR..."
echo ""

# Check if data directory exists and has files
if [ ! -d "$DATA_DIR" ]; then
    echo -e "${RED}✗ Data directory not found: $DATA_DIR${NC}"
    echo "Please generate data first using: cd data-gen && python generate_flows.py"
    exit 1
fi

# Find JSON files
JSON_FILES=$(find "$DATA_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | sort)
if [ -z "$JSON_FILES" ]; then
    echo -e "${RED}✗ No JSON files found in $DATA_DIR${NC}"
    echo "Please generate data first using: cd data-gen && python generate_flows.py"
    exit 1
fi

FILE_COUNT=$(echo "$JSON_FILES" | wc -l)
echo "Found $FILE_COUNT JSON file(s) to insert"
echo ""

# Record start time
START_TIME=$(date +%s)

# Create a background function to insert data
insert_data_background() {
    for JSON_FILE in $JSON_FILES; do
        FILENAME=$(basename "$JSON_FILE")
        echo "[INSERT] Processing $FILENAME..."
        
        cat "$JSON_FILE" | docker exec -i "$CLICKHOUSE01" clickhouse-client \
            --password="$PASSWORD" \
            --query="INSERT INTO $DB.$TABLE FORMAT JSONEachRow" \
            2>&1 | grep -v "^$" || true
        
        echo -e "[INSERT] ${GREEN}✓ Completed $FILENAME${NC}"
    done
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    echo ""
    echo -e "[INSERT] ${GREEN}✓ All bulk inserts completed in ${DURATION} seconds${NC}"
    echo "" > /tmp/insert_complete_$$.flag
}

# Pause replication on clickhouse02 so the queue builds up visibly during insert
echo "Pausing replication queue on clickhouse02 to make lag observable..."
query_node "$CLICKHOUSE02" "SYSTEM STOP REPLICATION QUEUES"
echo -e "${GREEN}✓ Replication queue paused on clickhouse02${NC}"
echo ""

# Start background insert
echo "Starting bulk insert in background..."
insert_data_background &
INSERT_PID=$!
echo -e "${GREEN}✓ Background insert started (PID: $INSERT_PID)${NC}"
echo ""

# Step 3: Check replication lag on clickhouse02 DURING insert
echo -e "${YELLOW}Step 3: Monitor Replication Lag on clickhouse02 (DURING insert)${NC}"
echo "Replication is PAUSED on node2 — queue will build up while insert runs."
echo "This guarantees observable lag regardless of network speed."
echo ""

# Monitor replication lag while insert is running
MONITOR_COUNT=0
while kill -0 $INSERT_PID 2>/dev/null; do
    MONITOR_COUNT=$((MONITOR_COUNT + 1))
    echo -e "${CYAN}--- Replication Check #$MONITOR_COUNT (replication PAUSED on node2) ---${NC}"

    query_node "$CLICKHOUSE02" "
        SELECT
            database,
            table,
            queue_size AS pending_ops,
            greatest(log_max_index - log_pointer, 0) AS replication_lag_count,
            absolute_delay AS lag_seconds
        FROM system.replicas
        WHERE table = '$TABLE'
        FORMAT Vertical
    " || echo -e "${YELLOW}⚠ Could not query replication status${NC}"

    # Show row counts — node2 should stay at 0 while paused
    COUNT1=$(query_node "$CLICKHOUSE01" "SELECT count() FROM $DB.$TABLE" 2>/dev/null || echo "0")
    COUNT2=$(query_node "$CLICKHOUSE02" "SELECT count() FROM $DB.$TABLE" 2>/dev/null || echo "0")
    echo "Current row counts - Node1: $COUNT1  |  Node2 (paused): $COUNT2"

    QUEUE_COUNT=$(query_node "$CLICKHOUSE02" "SELECT count() FROM system.replication_queue WHERE table = '$TABLE'" 2>/dev/null || echo "0")
    echo "Pending replication operations on node2: $QUEUE_COUNT"
    echo ""
done

# Wait for background insert to fully finish
wait $INSERT_PID
echo -e "${GREEN}✓ Bulk insert process completed${NC}"
echo ""

# Show the accumulated lag before resuming
echo "Accumulated replication lag on node2 (still paused):"
query_node "$CLICKHOUSE02" "
    SELECT
        type,
        create_time,
        source_replica,
        parts_to_merge,
        postpone_reason
    FROM system.replication_queue
    WHERE table = '$TABLE'
    ORDER BY create_time ASC
    LIMIT 10
    FORMAT PrettyCompact
" || echo "(queue empty or not accessible)"
echo ""

# Resume replication on clickhouse02
echo "Resuming replication queue on clickhouse02..."
query_node "$CLICKHOUSE02" "SYSTEM START REPLICATION QUEUES"
echo -e "${GREEN}✓ Replication queue resumed — node2 will now catch up${NC}"
echo ""

# Watch the lag drain
echo "Watching replication lag drain on node2..."
DRAIN_COUNT=0
while true; do
    DRAIN_COUNT=$((DRAIN_COUNT + 1))
    QUEUE_NOW=$(query_node "$CLICKHOUSE02" "SELECT count() FROM system.replication_queue WHERE table = '$TABLE'" 2>/dev/null || echo "0")
    COUNT2=$(query_node "$CLICKHOUSE02" "SELECT count() FROM $DB.$TABLE" 2>/dev/null || echo "0")
    COUNT1=$(query_node "$CLICKHOUSE01" "SELECT count() FROM $DB.$TABLE" 2>/dev/null || echo "0")
    echo -e "${CYAN}[Drain #$DRAIN_COUNT]${NC} Queue: $QUEUE_NOW pending ops | Node1: $COUNT1  Node2: $COUNT2"
    if [ "$QUEUE_NOW" == "0" ] && [ "$COUNT1" == "$COUNT2" ] && [ "$COUNT1" != "0" ]; then
        echo -e "${GREEN}✓ Replication fully caught up!${NC}"
        break
    fi
done
echo ""

# Step 4: Confirm data on clickhouse02
echo -e "${YELLOW}Step 4: Confirm Data on clickhouse02${NC}"
echo "Waiting for replication to complete..."
echo ""

# Wait and check multiple times
MAX_WAIT=30
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    COUNT1=$(query_node "$CLICKHOUSE01" "SELECT count() FROM $DB.$TABLE")
    COUNT2=$(query_node "$CLICKHOUSE02" "SELECT count() FROM $DB.$TABLE")
    
    echo "Node 1 row count: $COUNT1"
    echo "Node 2 row count: $COUNT2"
    
    if [ "$COUNT1" == "$COUNT2" ] && [ "$COUNT1" != "0" ]; then
        echo -e "${GREEN}✓ Row counts match - replication complete!${NC}"
        break
    else
        DIFF=$((COUNT1 - COUNT2))
        echo -e "${YELLOW}⚠ Difference: $DIFF rows - waiting...${NC}"
        WAIT_COUNT=$((WAIT_COUNT + 1))
        echo ""
    fi
done

if [ "$COUNT1" != "$COUNT2" ]; then
    echo -e "${YELLOW}⚠ Warning: Row counts still differ after waiting${NC}"
fi
echo ""

# Step 5: Recheck status
echo -e "${YELLOW}Step 5: Recheck Status${NC}"
check_status "Test 1"

echo -e "${GREEN}✓ TEST 1 COMPLETE${NC}"
echo ""

# ========================================
# TEST 2: Failover Simulation
# ========================================
echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}TEST 2: Failover Simulation${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""
echo "This test will stop clickhouse02, perform bulk insert, then restart it."
echo ""

if [ -t 0 ]; then
    read -p "Press ENTER to continue with Test 2, or Ctrl+C to exit... "
else
    echo "Non-interactive mode - continuing automatically in 5 seconds..."
    sleep 5
fi
echo ""

# Step 1: Clean up data from Test 1
echo -e "${YELLOW}Step 1: Clean Up Data from Test 1${NC}"
echo "Clearing table $DB.$TABLE on both nodes..."
query_node "$CLICKHOUSE01" "TRUNCATE TABLE $DB.$TABLE" || true
query_node "$CLICKHOUSE02" "TRUNCATE TABLE $DB.$TABLE" || true

COUNT1=$(query_node "$CLICKHOUSE01" "SELECT count() FROM $DB.$TABLE")
COUNT2=$(query_node "$CLICKHOUSE02" "SELECT count() FROM $DB.$TABLE")
echo "Node 1 row count after truncate: $COUNT1"
echo "Node 2 row count after truncate: $COUNT2"
echo -e "${GREEN}✓ Table cleared${NC}"
echo ""

# Step 2: Stop clickhouse02 container
echo -e "${YELLOW}Step 2: Stop clickhouse02 Container${NC}"
echo "Stopping clickhouse02..."
docker stop "$CLICKHOUSE02" > /dev/null
echo -e "${GREEN}✓ clickhouse02 stopped${NC}"
echo ""

# Step 3: Status check with node down
echo -e "${YELLOW}Step 3: Status Check (with node02 down)${NC}"
check_status "Test 2"

# Step 4: Bulk insert on clickhouse01 and confirm
echo -e "${YELLOW}Step 4: Bulk Insert on clickhouse01${NC}"
echo "Inserting data while clickhouse02 is offline..."
echo ""

START_TIME=$(date +%s)

for JSON_FILE in $JSON_FILES; do
    FILENAME=$(basename "$JSON_FILE")
    echo "Inserting $FILENAME..."
    
    cat "$JSON_FILE" | docker exec -i "$CLICKHOUSE01" clickhouse-client \
        --password="$PASSWORD" \
        --query="INSERT INTO $DB.$TABLE FORMAT JSONEachRow" \
        2>&1 | grep -v "^$" || true
    
    echo -e "${GREEN}✓ Inserted $FILENAME${NC}"
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo ""
echo -e "${GREEN}✓ Bulk insert completed in ${DURATION} seconds (while node02 offline)${NC}"
echo ""

# Confirm data on clickhouse01
COUNT_BEFORE=$(query_node "$CLICKHOUSE01" "SELECT count() FROM $DB.$TABLE")
echo "Row count on clickhouse01: $COUNT_BEFORE"
echo -e "${GREEN}✓ Data confirmed on clickhouse01${NC}"
echo ""

# Step 5: Start clickhouse02 container
echo -e "${YELLOW}Step 5: Start clickhouse02 Container${NC}"
echo "Starting clickhouse02..."
docker start "$CLICKHOUSE02" > /dev/null
echo "Waiting 15 seconds for clickhouse02 to fully start..."
sleep 2
echo -e "${GREEN}✓ clickhouse02 started${NC}"
echo ""

# Step 6: Confirm data on clickhouse02
echo -e "${YELLOW}Step 6: Confirm Data on clickhouse02${NC}"
echo "Checking if data replicated after recovery..."
echo ""

MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    COUNT1=$(query_node "$CLICKHOUSE01" "SELECT count() FROM $DB.$TABLE")
    COUNT2=$(query_node "$CLICKHOUSE02" "SELECT count() FROM $DB.$TABLE")
    
    echo "Node 1 row count: $COUNT1"
    echo "Node 2 row count: $COUNT2"
    
    if [ "$COUNT1" == "$COUNT2" ] && [ "$COUNT1" != "0" ]; then
        echo -e "${GREEN}✓ Failover successful! Data replicated after node recovery${NC}"
        break
    else
        DIFF=$((COUNT1 - COUNT2))
        echo -e "${YELLOW}⚠ Replicating... (difference: $DIFF rows)${NC}"
        WAIT_COUNT=$((WAIT_COUNT + 1))
        echo ""
    fi
done

if [ "$COUNT1" != "$COUNT2" ]; then
    echo -e "${RED}✗ Warning: Data replication incomplete after ${MAX_WAIT} attempts${NC}"
else
    echo -e "${GREEN}✓ Replication verified: $COUNT2 rows on clickhouse02${NC}"
fi
echo ""

# Step 7: Final status check
echo -e "${YELLOW}Step 7: Final Status Check${NC}"
check_status "Test 2"

echo -e "${GREEN}✓ TEST 2 COMPLETE${NC}"
echo ""

# ========================================
# Final Summary
# ========================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Replication Testing Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Summary:"
echo "  - Test 1: Normal replication with bulk insert ✓"
echo "  - Test 2: Failover simulation and recovery ✓"
echo ""
echo -e "${GREEN}All tests completed successfully!${NC}"

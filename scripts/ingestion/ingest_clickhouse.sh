#!/bin/bash
# Script: ingest_clickhouse.sh
# Purpose: Ingest JSONEachRow flow data into ClickHouse
# Usage: ./ingest_clickhouse.sh [data_directory]
# Author: NetFlow Analytics Team
# Date: 2026-03-16

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${1:-${SCRIPT_DIR}/../../data-gen/output}"
CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-8123}"
CH_DB="${CH_DB:-netflow}"
CH_TABLE="${CH_TABLE:-flows_local}"
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD:-admin}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "ClickHouse Data Ingestion"
echo "========================================"
echo ""
echo "Configuration:"
echo "  ClickHouse:  ${CH_HOST}:${CH_PORT}"
echo "  Database:    ${CH_DB}"
echo "  Table:       ${CH_TABLE}"
echo "  Data dir:    ${DATA_DIR}"
echo ""

# Check if data directory exists
if [ ! -d "$DATA_DIR" ]; then
    echo -e "${RED}ERROR: Data directory not found: ${DATA_DIR}${NC}"
    echo "Please generate data first: cd ../../data-gen && python generate_flows.py"
    exit 1
fi

# Count JSON files
json_files=("${DATA_DIR}"/flows_*.json)
if [ ! -f "${json_files[0]}" ]; then
    echo -e "${RED}ERROR: No flows_*.json files found in ${DATA_DIR}${NC}"
    exit 1
fi

file_count=${#json_files[@]}
echo "Found ${file_count} data file(s) to ingest"
echo ""

# Get initial row count
echo "Checking initial row count..."
initial_count=$(curl -s -u "${CH_USER}:${CH_PASSWORD}" "http://${CH_HOST}:${CH_PORT}/?query=SELECT%20count()%20FROM%20${CH_DB}.${CH_TABLE}" || echo "0")
echo "Initial rows: $(printf "%'d" ${initial_count} 2>/dev/null || echo ${initial_count})"
echo ""

# Ingest files
echo "========================================"
echo "Starting ingestion..."
echo "========================================"
echo ""

start_time=$(date +%s)
total_bytes=0
file_num=0

for file in "${json_files[@]}"; do
    file_num=$((file_num + 1))
    filename=$(basename "$file")
    filesize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    filesize_mb=$(echo "scale=2; $filesize / 1024 / 1024" | bc)
    
    echo -e "${BLUE}[$file_num/$file_count]${NC} Ingesting ${filename} (${filesize_mb} MB)..."
    
    file_start=$(date +%s)
    
    # Insert data via HTTP interface
    cat "$file" | curl -s -X POST \
        -u "${CH_USER}:${CH_PASSWORD}" \
        "http://${CH_HOST}:${CH_PORT}/?query=INSERT%20INTO%20${CH_DB}.${CH_TABLE}%20FORMAT%20JSONEachRow" \
        --data-binary @- \
        -o /tmp/ch_insert_result.txt
    
    file_end=$(date +%s)
    file_elapsed=$((file_end - file_start))
    
    # Check for errors
    if grep -q "Exception" /tmp/ch_insert_result.txt 2>/dev/null; then
        echo -e "${RED}FAILED${NC}"
        echo "Error details:"
        cat /tmp/ch_insert_result.txt
        exit 1
    fi
    
    # Calculate throughput
    if [ $file_elapsed -gt 0 ]; then
        throughput_mb=$(echo "scale=2; $filesize_mb / $file_elapsed" | bc)
    else
        throughput_mb="N/A"
    fi
    
    total_bytes=$((total_bytes + filesize))
    
    echo -e "  ${GREEN}✓${NC} Complete in ${file_elapsed}s (${throughput_mb} MB/s)"
    
    # Show progress
    current_count=$(curl -s -u "${CH_USER}:${CH_PASSWORD}" "http://${CH_HOST}:${CH_PORT}/?query=SELECT%20count()%20FROM%20${CH_DB}.${CH_TABLE}")
    new_rows=$((current_count - initial_count))
    echo -e "  Total rows now: $(printf "%'d" ${current_count} 2>/dev/null || echo ${current_count}) (+$(printf "%'d" ${new_rows} 2>/dev/null || echo ${new_rows}))"
    echo ""
done

end_time=$(date +%s)
total_elapsed=$((end_time - start_time))

# Final statistics
echo "========================================"
echo -e "${GREEN}✓ Ingestion Complete!${NC}"
echo "========================================"
echo ""

final_count=$(curl -s -u "${CH_USER}:${CH_PASSWORD}" "http://${CH_HOST}:${CH_PORT}/?query=SELECT%20count()%20FROM%20${CH_DB}.${CH_TABLE}")
rows_inserted=$((final_count - initial_count))
total_mb=$(echo "scale=2; $total_bytes / 1024 / 1024" | bc)

if [ $total_elapsed -gt 0 ]; then
    avg_throughput_mb=$(echo "scale=2; $total_mb / $total_elapsed" | bc)
    avg_throughput_rows=$(echo "scale=0; $rows_inserted / $total_elapsed" | bc)
else
    avg_throughput_mb="N/A"
    avg_throughput_rows="N/A"
fi

echo "Statistics:"
echo "  Files processed:    ${file_count}"
echo "  Total data:         ${total_mb} MB"
echo "  Rows inserted:      $(printf "%'d" ${rows_inserted} 2>/dev/null || echo ${rows_inserted})"
echo "  Total time:         ${total_elapsed} seconds"
echo "  Avg throughput:     ${avg_throughput_mb} MB/s"
echo "  Avg insert rate:    $(printf "%'d" ${avg_throughput_rows} 2>/dev/null || echo ${avg_throughput_rows}) rows/s"
echo ""
echo "Final row count:      $(printf "%'d" ${final_count} 2>/dev/null || echo ${final_count})"
echo ""
echo "Next steps:"
echo "  - Verify data: docker exec -it clickhouse01 clickhouse-client --query 'SELECT count() FROM flows_local'"
echo "  - Run queries: cd ../../sql/queries && cat verify_data.sql | docker exec -i clickhouse01 clickhouse-client"
echo "  - Monitor: ./monitor_ingestion.sh"
echo ""

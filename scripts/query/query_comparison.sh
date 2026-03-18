#!/bin/bash
# Script: query_comparison.sh
# Purpose: Compare query performance between ClickHouse and InfluxDB over multiple runs
# Usage: ./query_comparison.sh
# Author: NetFlow Analytics Team
# Date: 2026-03-16

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../../benchmark-results/query"
OUTPUT_FILE="${OUTPUT_DIR}/query-comparison-results.txt"
NUM_RUNS=5  # Can be changed to any number (e.g., 3, 5, 7, 10) - tables will adjust dynamically

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"

# Temporary files for storing run data
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}Query Performance Comparison${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Running ${NUM_RUNS} iterations of query tests..."
echo ""

# Clear caches before tests to ensure fair comparison
echo -e "${YELLOW}→${NC} Clearing database caches..."

# # Clear ClickHouse caches
# docker exec clickhouse01 clickhouse-client --query="SYSTEM DROP MARK CACHE" 2>/dev/null || true
# docker exec clickhouse01 clickhouse-client --query="SYSTEM DROP UNCOMPRESSED CACHE" 2>/dev/null || true
# docker exec clickhouse01 clickhouse-client --query="SYSTEM DROP COMPILED EXPRESSION CACHE" 2>/dev/null || true
# docker exec clickhouse01 clickhouse-client --query="SYSTEM DROP QUERY CACHE" 2>/dev/null || true

# # For InfluxDB, we can clear OS page cache or restart (restart is too heavy, so we skip for now)
# # InfluxDB uses OS-level caching which we can't easily clear without root access
# # The multiple runs will still give us good average performance

docker restart clickhouse01 && docker restart influxdb
sleep 10

echo -e "${GREEN}✓${NC} Caches cleared"
echo ""

# Run tests multiple times
for run in $(seq 1 ${NUM_RUNS}); do
    echo -e "${BLUE}[Run ${run}/${NUM_RUNS}]${NC} Executing query tests..."
    
    # Run ClickHouse queries
    echo -e "  ${YELLOW}→${NC} Running ClickHouse queries..."
    python3 "${SCRIPT_DIR}/query_clickhouse.py" > /dev/null 2>&1
    
    # Extract timings and save to temp file
    grep "Elapsed Time:" "${OUTPUT_DIR}/query-clickhouse-output.txt" | \
        sed -n 's/Elapsed Time: \([0-9.]*\) ms/\1/p' > "${TMP_DIR}/ch_run${run}.txt"
    
    # Run InfluxDB queries
    echo -e "  ${YELLOW}→${NC} Running InfluxDB queries..."
    python3 "${SCRIPT_DIR}/query_influxdb.py" > /dev/null 2>&1
    
    # Extract timings and save to temp file
    grep "Elapsed Time:" "${OUTPUT_DIR}/query-influxdb-output.txt" | \
        sed -n 's/Elapsed Time: \([0-9.]*\) ms/\1/p' > "${TMP_DIR}/influx_run${run}.txt"
    
    echo -e "  ${GREEN}✓${NC} Run ${run} complete"
done

echo ""
echo -e "${YELLOW}→${NC} Generating report..."

# Extract query names from one of the output files
grep "Query:" "${OUTPUT_DIR}/query-clickhouse-output.txt" | \
    sed 's/Query: //' > "${TMP_DIR}/query_names.txt"

# Count queries
NUM_QUERIES=$(wc -l < "${TMP_DIR}/query_names.txt")

# Initialize output file
cat > "${OUTPUT_FILE}" << EOF
========================================
Query Performance Comparison Report
ClickHouse vs InfluxDB
========================================

Date: $(date '+%Y-%m-%d %H:%M:%S')
Number of runs: ${NUM_RUNS}
Number of queries: ${NUM_QUERIES}

========================================
RESULTS (Average of ${NUM_RUNS} runs)
========================================

EOF

# Add table header
printf "%-50s | %12s | %12s | %10s | %s\n" "Query" "ClickHouse" "InfluxDB" "Speedup" "Winner" >> "${OUTPUT_FILE}"
printf '%s\n' "$(printf '=%.0s' {1..100})" >> "${OUTPUT_FILE}"

# Process each query
query_num=0
total_ch=0
total_influx=0
ch_wins=0
influx_wins=0

while IFS= read -r query_name; do
    query_num=$((query_num + 1))
    
    # Calculate ClickHouse average
    ch_sum=0
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${query_num}p" "${TMP_DIR}/ch_run${run}.txt")
        ch_sum=$(awk "BEGIN {print $ch_sum + $time}")
    done
    ch_avg=$(awk "BEGIN {printf \"%.2f\", $ch_sum / $NUM_RUNS}")
    
    # Calculate InfluxDB average
    influx_sum=0
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${query_num}p" "${TMP_DIR}/influx_run${run}.txt")
        influx_sum=$(awk "BEGIN {print $influx_sum + $time}")
    done
    influx_avg=$(awk "BEGIN {printf \"%.2f\", $influx_sum / $NUM_RUNS}")
    
    # Calculate speedup and winner
    if (( $(awk "BEGIN {print ($ch_avg < $influx_avg)}") )); then
        speedup=$(awk "BEGIN {printf \"%.2f\", $influx_avg / $ch_avg}")
        winner="ClickHouse"
        ch_wins=$((ch_wins + 1))
    else
        speedup=$(awk "BEGIN {printf \"%.2f\", $ch_avg / $influx_avg}")
        winner="InfluxDB"
        influx_wins=$((influx_wins + 1))
    fi
    
    # Truncate query name if too long
    short_query=$(echo "$query_name" | cut -c 1-49)
    
    # Write to output
    echo "$short_query" | awk -v ch="$ch_avg" -v inf="$influx_avg" -v sp="$speedup" -v w="$winner" \
        '{printf "%-50s | %10.2f ms | %10.2f ms | %8.2fx | %s\n", $0, ch, inf, sp, w}' >> "${OUTPUT_FILE}"
    
    # Add to totals
    total_ch=$(awk "BEGIN {print $total_ch + $ch_avg}")
    total_influx=$(awk "BEGIN {print $total_influx + $influx_avg}")
    
done < "${TMP_DIR}/query_names.txt"

# Summary
printf '%s\n' "$(printf '=%.0s' {1..100})" >> "${OUTPUT_FILE}"
echo "TOTAL" | awk -v ch="$total_ch" -v inf="$total_influx" \
    '{printf "%-50s | %10.2f ms | %10.2f ms |\n", $0, ch, inf}' >> "${OUTPUT_FILE}"

# Add detailed tables for each database showing all runs
echo "" >> "${OUTPUT_FILE}"
echo "========================================" >> "${OUTPUT_FILE}"
echo "CLICKHOUSE - Detailed Results (All ${NUM_RUNS} runs)" >> "${OUTPUT_FILE}"
echo "========================================" >> "${OUTPUT_FILE}"
echo "" >> "${OUTPUT_FILE}"

# Build ClickHouse table header dynamically
ch_header="Query"
for run in $(seq 1 ${NUM_RUNS}); do
    ch_header="${ch_header}|Run${run}"
done
echo "$ch_header" | awk -F'|' '{
    printf "%-50s", $1
    for(i=2; i<=NF; i++) printf " | %10s", $i
    print ""
}' >> "${OUTPUT_FILE}"

# Print separator
col_width=$((50 + (NUM_RUNS * 13) + 3))
printf '%s\n' "$(head -c $col_width < /dev/zero | tr '\0' '=')" >> "${OUTPUT_FILE}"

# Print ClickHouse data for each query
query_num=0
while IFS= read -r query_name; do
    query_num=$((query_num + 1))
    short_query=$(echo "$query_name" | cut -c 1-49)
    
    # Collect all run times
    run_times=""
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${query_num}p" "${TMP_DIR}/ch_run${run}.txt")
        run_times="${run_times}|${time}"
    done
    
    # Print row
    echo "${short_query}${run_times}" | awk -F'|' '{
        printf "%-50s", $1
        for(i=2; i<=NF; i++) printf " | %8.2f ms", $i
        print ""
    }' >> "${OUTPUT_FILE}"
done < "${TMP_DIR}/query_names.txt"

echo "" >> "${OUTPUT_FILE}"
echo "========================================" >> "${OUTPUT_FILE}"
echo "INFLUXDB - Detailed Results (All ${NUM_RUNS} runs)" >> "${OUTPUT_FILE}"
echo "========================================" >> "${OUTPUT_FILE}"
echo "" >> "${OUTPUT_FILE}"

# Build InfluxDB table header (same structure)
echo "$ch_header" | awk -F'|' '{
    printf "%-50s", $1
    for(i=2; i<=NF; i++) printf " | %10s", $i
    print ""
}' >> "${OUTPUT_FILE}"

# Print separator
printf '%s\n' "$(head -c $col_width < /dev/zero | tr '\0' '=')" >> "${OUTPUT_FILE}"

# Print InfluxDB data for each query
query_num=0
while IFS= read -r query_name; do
    query_num=$((query_num + 1))
    short_query=$(echo "$query_name" | cut -c 1-49)
    
    # Collect all run times
    run_times=""
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${query_num}p" "${TMP_DIR}/influx_run${run}.txt")
        run_times="${run_times}|${time}"
    done
    
    # Print row
    echo "${short_query}${run_times}" | awk -F'|' '{
        printf "%-50s", $1
        for(i=2; i<=NF; i++) printf " | %8.2f ms", $i
        print ""
    }' >> "${OUTPUT_FILE}"
done < "${TMP_DIR}/query_names.txt"

cat >> "${OUTPUT_FILE}" << EOF

========================================
SUMMARY
========================================

Total queries: ${NUM_QUERIES}
ClickHouse wins: ${ch_wins}
InfluxDB wins: ${influx_wins}

Average query time:
  ClickHouse: $(awk "BEGIN {printf \"%.2f\", $total_ch / $NUM_QUERIES}") ms
  InfluxDB:   $(awk "BEGIN {printf \"%.2f\", $total_influx / $NUM_QUERIES}") ms

EOF

# Overall winner
avg_ch=$(awk "BEGIN {printf \"%.2f\", $total_ch / $NUM_QUERIES}")
avg_influx=$(awk "BEGIN {printf \"%.2f\", $total_influx / $NUM_QUERIES}")

if (( $(awk "BEGIN {print ($avg_ch < $avg_influx)}") )); then
    overall_speedup=$(awk "BEGIN {printf \"%.2f\", $avg_influx / $avg_ch}")
    overall_pct=$(awk "BEGIN {printf \"%.1f\", ($avg_influx - $avg_ch) / $avg_influx * 100}")
    echo "Overall Winner: ClickHouse (${overall_speedup}x faster, ${overall_pct}% improvement)" >> "${OUTPUT_FILE}"
else
    overall_speedup=$(awk "BEGIN {printf \"%.2f\", $avg_ch / $avg_influx}")
    overall_pct=$(awk "BEGIN {printf \"%.1f\", ($avg_ch - $avg_influx) / $avg_ch * 100}")
    echo "Overall Winner: InfluxDB (${overall_speedup}x faster, ${overall_pct}% improvement)" >> "${OUTPUT_FILE}"
fi

echo "========================================" >> "${OUTPUT_FILE}"

# Print summary to console
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}✓ Comparison Complete!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Results: ${OUTPUT_FILE}"
echo ""
echo -e "${BOLD}Summary:${NC}"
echo "  Total queries: ${NUM_QUERIES}"
echo "  ClickHouse wins: ${ch_wins}"
echo "  InfluxDB wins: ${influx_wins}"
echo "  Average: ClickHouse ${avg_ch} ms vs InfluxDB ${avg_influx} ms"
echo ""
if (( $(awk "BEGIN {print ($avg_ch < $avg_influx)}") )); then
    echo -e "  ${GREEN}Winner: ClickHouse (${overall_speedup}x faster)${NC}"
else
    echo -e "  ${GREEN}Winner: InfluxDB (${overall_speedup}x faster)${NC}"
fi
echo ""

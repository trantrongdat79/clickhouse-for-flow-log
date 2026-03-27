#!/bin/bash
# Script: ingest_comparison.sh
# Purpose: Comprehensive benchmark comparison between ClickHouse and InfluxDB ingestion
# Usage: ./ingest_comparison.sh
# Author: NetFlow Analytics Team
# Date: 2026-03-18

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================
NUM_RUNS=3  # Number of times to repeat the benchmark

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================================================
# Paths
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOCKER_DIR="${PROJECT_ROOT}/docker"
SETUP_SCRIPT="${PROJECT_ROOT}/scripts/setup/02-init-schema.sh"
INGEST_CH_SCRIPT="${SCRIPT_DIR}/ingest_clickhouse.py"
INGEST_INFLUX_SCRIPT="${SCRIPT_DIR}/ingest_influxdb.py"
OUTPUT_DIR="${PROJECT_ROOT}/benchmark-results/ingest"
COMPARISON_OUTPUT="${OUTPUT_DIR}/ingest-comparison-results.txt"
CH_OUTPUT="${OUTPUT_DIR}/ingest-clickhouse-output.txt"
INFLUX_OUTPUT="${OUTPUT_DIR}/ingest-influxdb-output.txt"

# ============================================================================
# Functions
# ============================================================================

print_banner() {
    echo ""
    echo "============================================================================"
    echo -e "${BOLD}$1${NC}"
    echo "============================================================================"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

wait_for_container_healthy() {
    local container_name=$1
    local max_attempts=60
    local attempt=0
    
    print_step "Waiting for ${container_name} to be healthy..."
    
    while [ $attempt -lt $max_attempts ]; do
        if docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null | grep -q "healthy"; then
            print_success "${container_name} is healthy"
            return 0
        fi
        
        # If no health check, just check if running
        if docker ps --filter "name=${container_name}" --filter "status=running" | grep -q "${container_name}"; then
            # Give it a few more seconds
            if [ $attempt -gt 10 ]; then
                print_success "${container_name} is running"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        sleep 1
    done
    
    print_error "${container_name} did not become healthy in time"
    return 1
}

cleanup() {
    print_step "Cleaning up containers and data..."
    
    # Go to docker directory
    cd "${DOCKER_DIR}"
    
    # Stop and remove containers, volumes, and orphans
    docker compose down -v --remove-orphans 2>/dev/null || true
    
    # Remove InfluxDB data directory (ClickHouse uses named volume, handled by docker compose down -v)
    rm -rf "${PROJECT_ROOT}/data/influxdb"/* 2>/dev/null || true
    
    # Also clean up logs and other data directories to start fresh
    rm -rf "${PROJECT_ROOT}/logs"/* 2>/dev/null || true
        
    print_success "Cleanup complete"
}

start_containers() {
    print_step "Starting containers..."
    
    cd "${DOCKER_DIR}"
    
    # Start containers in detached mode
    docker compose up -d
    
    if [ $? -ne 0 ]; then
        print_error "Failed to start containers"
        exit 1
    fi
    
    print_success "Containers started"
    
    # Wait for containers to be healthy
    wait_for_container_healthy "clickhouse01"
    wait_for_container_healthy "influxdb"
    
    # Give them a bit more time to fully initialize
    sleep 5
}

initialize_schema() {
    print_step "Initializing ClickHouse schema..."
    
    # Run the schema initialization script
    bash "${SETUP_SCRIPT}"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to initialize ClickHouse schema"
        exit 1
    fi
    
    print_success "ClickHouse schema initialized"
}

run_ingestion() {
    local run_number=$1
    
    print_banner "Run ${run_number}/${NUM_RUNS}: Ingestion Benchmark"
    
    # Run ClickHouse ingestion
    print_step "Running ClickHouse ingestion..."
    cd "${SCRIPT_DIR}"
    python3 ingest_clickhouse.py
    
    if [ $? -ne 0 ]; then
        print_error "ClickHouse ingestion failed"
        return 1
    fi
    print_success "ClickHouse ingestion complete"
    
    # Run InfluxDB ingestion
    print_step "Running InfluxDB ingestion..."
    python3 ingest_influxdb.py
    
    if [ $? -ne 0 ]; then
        print_error "InfluxDB ingestion failed"
        return 1
    fi
    print_success "InfluxDB ingestion complete"
    
    return 0
}

collect_results() {
    local run_number=$1
    
    print_step "Collecting results for Run ${run_number}..."
    
    # Create output directory if it doesn't exist
    mkdir -p "${OUTPUT_DIR}"
    
    # Extract ClickHouse metrics and save to temp files
    if [ -f "${CH_OUTPUT}" ]; then
        grep "^Ingestion Time:" "${CH_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/ch_ingest_times.txt"
        grep "^Pre-compaction Storage:" "${CH_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/ch_pre_storage.txt"
        grep "^Compaction Time:" "${CH_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/ch_compact_times.txt"
        grep "^Post-compaction Storage:" "${CH_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/ch_post_storage.txt"
        grep "^Compression Ratio:" "${CH_OUTPUT}" | awk '{print $3}' | sed 's/%//' >> "${OUTPUT_DIR}/ch_compression.txt"
    else
        echo "0" >> "${OUTPUT_DIR}/ch_ingest_times.txt"
        echo "0" >> "${OUTPUT_DIR}/ch_pre_storage.txt"
        echo "0" >> "${OUTPUT_DIR}/ch_compact_times.txt"
        echo "0" >> "${OUTPUT_DIR}/ch_post_storage.txt"
        echo "0" >> "${OUTPUT_DIR}/ch_compression.txt"
    fi
    
    # Extract InfluxDB metrics and save to temp files
    if [ -f "${INFLUX_OUTPUT}" ]; then
        grep "^Ingestion Time:" "${INFLUX_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/influx_ingest_times.txt"
        grep "^Pre-compaction Storage:" "${INFLUX_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/influx_pre_storage.txt"
        grep "^Compaction Time:" "${INFLUX_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/influx_compact_times.txt"
        grep "^Post-compaction Storage:" "${INFLUX_OUTPUT}" | awk '{print $3}' >> "${OUTPUT_DIR}/influx_post_storage.txt"
        grep "^Compression Ratio:" "${INFLUX_OUTPUT}" | awk '{print $3}' | sed 's/%//' >> "${OUTPUT_DIR}/influx_compression.txt"
    else
        echo "0" >> "${OUTPUT_DIR}/influx_ingest_times.txt"
        echo "0" >> "${OUTPUT_DIR}/influx_pre_storage.txt"
        echo "0" >> "${OUTPUT_DIR}/influx_compact_times.txt"
        echo "0" >> "${OUTPUT_DIR}/influx_post_storage.txt"
        echo "0" >> "${OUTPUT_DIR}/influx_compression.txt"
    fi
    
    print_success "Results collected for Run ${run_number}"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_banner "ClickHouse vs InfluxDB Ingestion Benchmark"
    
    echo "Configuration:"
    echo "  Number of runs: ${NUM_RUNS}"
    echo "  Project root:   ${PROJECT_ROOT}"
    echo "  Docker dir:     ${DOCKER_DIR}"
    echo "  Output file:    ${COMPARISON_OUTPUT}"
    
    # Create output directory
    mkdir -p "${OUTPUT_DIR}"
    
    # Clean up any previous temp files
    rm -f "${OUTPUT_DIR}"/ch_*.txt "${OUTPUT_DIR}"/influx_*.txt
    
    # Run benchmarks
    for run in $(seq 1 ${NUM_RUNS}); do
        echo ""
        print_banner "Starting Run ${run}/${NUM_RUNS}"
        
        # Step 1: Cleanup
        cleanup
        
        # Step 2: Start containers
        start_containers
        
        # Step 3: Initialize schema
        initialize_schema
        
        # Step 4: Run ingestion
        run_ingestion ${run}
        
        if [ $? -ne 0 ]; then
            print_error "Run ${run} failed"
            continue
        fi
        
        # Step 5: Collect results
        collect_results ${run}
        
        print_success "Run ${run} complete"
        
        # Brief pause between runs
        if [ ${run} -lt ${NUM_RUNS} ]; then
            echo ""
            print_step "Pausing before next run..."
            sleep 3
        fi
    done
    
    # Calculate and append summary statistics
    print_banner "Generating Report"
    
    # Calculate averages for each metric
    ch_avg_ingest=$(awk '{sum+=$1} END {printf "%.2f", sum/NR}' "${OUTPUT_DIR}/ch_ingest_times.txt")
    ch_avg_pre=$(awk '{sum+=$1} END {printf "%.2f", sum/NR/1048576}' "${OUTPUT_DIR}/ch_pre_storage.txt")
    ch_avg_compact=$(awk '{sum+=$1} END {printf "%.2f", sum/NR}' "${OUTPUT_DIR}/ch_compact_times.txt")
    ch_avg_post=$(awk '{sum+=$1} END {printf "%.2f", sum/NR/1048576}' "${OUTPUT_DIR}/ch_post_storage.txt")
    ch_avg_compression=$(awk '{sum+=$1} END {printf "%.2f", sum/NR}' "${OUTPUT_DIR}/ch_compression.txt")
    
    influx_avg_ingest=$(awk '{sum+=$1} END {printf "%.2f", sum/NR}' "${OUTPUT_DIR}/influx_ingest_times.txt")
    influx_avg_pre=$(awk '{sum+=$1} END {printf "%.2f", sum/NR/1048576}' "${OUTPUT_DIR}/influx_pre_storage.txt")
    influx_avg_compact=$(awk '{sum+=$1} END {printf "%.2f", sum/NR}' "${OUTPUT_DIR}/influx_compact_times.txt")
    influx_avg_post=$(awk '{sum+=$1} END {printf "%.2f", sum/NR/1048576}' "${OUTPUT_DIR}/influx_post_storage.txt")
    influx_avg_compression=$(awk '{sum+=$1} END {printf "%.2f", sum/NR}' "${OUTPUT_DIR}/influx_compression.txt")
    
    # Initialize comparison output file with header
    cat > "${COMPARISON_OUTPUT}" << EOF
========================================
Ingestion Performance Comparison Report
ClickHouse vs InfluxDB
========================================

Date: $(date '+%Y-%m-%d %H:%M:%S')
Number of runs: ${NUM_RUNS}

========================================
RESULTS (Average of ${NUM_RUNS} run(s))
========================================

EOF
    
    # Add summary table header
    printf "%-45s | %13s | %13s | %10s | %s\n" "Metric" "ClickHouse" "InfluxDB" "Speedup" "Winner" >> "${COMPARISON_OUTPUT}"
    printf '%s\n' "$(printf '=%.0s' {1..105})" >> "${COMPARISON_OUTPUT}"
    
    # Track wins
    ch_wins=0
    influx_wins=0
    
    # Metric 1: Ingestion Time
    if (( $(awk "BEGIN {print ($ch_avg_ingest < $influx_avg_ingest)}") )); then
        speedup=$(awk "BEGIN {printf \"%.2f\", $influx_avg_ingest / $ch_avg_ingest}")
        winner="ClickHouse"
        ch_wins=$((ch_wins + 1))
    else
        speedup=$(awk "BEGIN {printf \"%.2f\", $ch_avg_ingest / $influx_avg_ingest}")
        winner="InfluxDB"
        influx_wins=$((influx_wins + 1))
    fi
    awk -v ch="$ch_avg_ingest" -v inf="$influx_avg_ingest" -v sp="$speedup" -v w="$winner" \
        'BEGIN {printf "%-45s | %10.2f ms | %10.2f ms | %8.2fx | %s\n", "Ingestion Time", ch, inf, sp, w}' >> "${COMPARISON_OUTPUT}"
    
    # Metric 2: Pre-compaction Storage
    if (( $(awk "BEGIN {print ($ch_avg_pre < $influx_avg_pre)}") )); then
        speedup=$(awk "BEGIN {printf \"%.2f\", $influx_avg_pre / $ch_avg_pre}")
        winner="ClickHouse"
        ch_wins=$((ch_wins + 1))
    else
        speedup=$(awk "BEGIN {printf \"%.2f\", $ch_avg_pre / $influx_avg_pre}")
        winner="InfluxDB"
        influx_wins=$((influx_wins + 1))
    fi
    awk -v ch="$ch_avg_pre" -v inf="$influx_avg_pre" -v sp="$speedup" -v w="$winner" \
        'BEGIN {printf "%-45s | %10.2f MB | %10.2f MB | %8.2fx | %s\n", "Pre-compaction Storage", ch, inf, sp, w}' >> "${COMPARISON_OUTPUT}"
    
    # Metric 3: Compaction Time
    if (( $(awk "BEGIN {print ($ch_avg_compact < $influx_avg_compact)}") )); then
        speedup=$(awk "BEGIN {printf \"%.2f\", $influx_avg_compact / $ch_avg_compact}")
        winner="ClickHouse"
        ch_wins=$((ch_wins + 1))
    else
        speedup=$(awk "BEGIN {printf \"%.2f\", $ch_avg_compact / $influx_avg_compact}")
        winner="InfluxDB"
        influx_wins=$((influx_wins + 1))
    fi
    awk -v ch="$ch_avg_compact" -v inf="$influx_avg_compact" -v sp="$speedup" -v w="$winner" \
        'BEGIN {printf "%-45s | %10.2f ms | %10.2f ms | %8.2fx | %s\n", "Compaction Time", ch, inf, sp, w}' >> "${COMPARISON_OUTPUT}"
    
    # Metric 4: Post-compaction Storage
    if (( $(awk "BEGIN {print ($ch_avg_post < $influx_avg_post)}") )); then
        speedup=$(awk "BEGIN {printf \"%.2f\", $influx_avg_post / $ch_avg_post}")
        winner="ClickHouse"
        ch_wins=$((ch_wins + 1))
    else
        speedup=$(awk "BEGIN {printf \"%.2f\", $ch_avg_post / $influx_avg_post}")
        winner="InfluxDB"
        influx_wins=$((influx_wins + 1))
    fi
    awk -v ch="$ch_avg_post" -v inf="$influx_avg_post" -v sp="$speedup" -v w="$winner" \
        'BEGIN {printf "%-45s | %10.2f MB | %10.2f MB | %8.2fx | %s\n", "Post-compaction Storage", ch, inf, sp, w}' >> "${COMPARISON_OUTPUT}"
    
    # Metric 5: Compression Ratio (higher is better)
    if (( $(awk "BEGIN {print ($ch_avg_compression > $influx_avg_compression)}") )); then
        speedup=$(awk "BEGIN {printf \"%.2f\", $ch_avg_compression / $influx_avg_compression}")
        winner="ClickHouse"
        ch_wins=$((ch_wins + 1))
    else
        speedup=$(awk "BEGIN {printf \"%.2f\", $influx_avg_compression / $ch_avg_compression}")
        winner="InfluxDB"
        influx_wins=$((influx_wins + 1))
    fi
    awk -v ch="$ch_avg_compression" -v inf="$influx_avg_compression" -v sp="$speedup" -v w="$winner" \
        'BEGIN {printf "%-45s | %10.2f %% | %10.2f %% | %8.2fx | %s\n", "Compression Ratio", ch, inf, sp, w}' >> "${COMPARISON_OUTPUT}"
    
    # Add totals line
    printf '%s\n' "$(printf '=%.0s' {1..105})" >> "${COMPARISON_OUTPUT}"
    
    # Add detailed ClickHouse table
    cat >> "${COMPARISON_OUTPUT}" << EOF

========================================
CLICKHOUSE - Detailed Results (All ${NUM_RUNS} run(s))
========================================

EOF
    
    # Build ClickHouse table header dynamically
    ch_header="Metric"
    for run in $(seq 1 ${NUM_RUNS}); do
        ch_header="${ch_header}|Run${run}"
    done
    
    echo "$ch_header" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %12s", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Print separator
    col_width=$((45 + (NUM_RUNS * 15) + 3))
    printf '%s\n' "$(head -c $col_width < /dev/zero | tr '\0' '=')" >> "${COMPARISON_OUTPUT}"
    
    # Print ClickHouse data
    # Row 1: Ingestion Time
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${run}p" "${OUTPUT_DIR}/ch_ingest_times.txt")
        runs_data="${runs_data}|${time}"
    done
    echo "Ingestion Time (ms)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 2: Pre-compaction Storage (convert Bytes to MB)
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        bytes=$(sed -n "${run}p" "${OUTPUT_DIR}/ch_pre_storage.txt")
        mb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1048576}")
        runs_data="${runs_data}|${mb}"
    done
    echo "Pre-compaction Storage (MB)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 3: Compaction Time
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${run}p" "${OUTPUT_DIR}/ch_compact_times.txt")
        runs_data="${runs_data}|${time}"
    done
    echo "Compaction Time (ms)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 4: Post-compaction Storage (convert Bytes to MB)
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        bytes=$(sed -n "${run}p" "${OUTPUT_DIR}/ch_post_storage.txt")
        mb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1048576}")
        runs_data="${runs_data}|${mb}"
    done
    echo "Post-compaction Storage (MB)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 5: Compression Ratio
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        ratio=$(sed -n "${run}p" "${OUTPUT_DIR}/ch_compression.txt")
        runs_data="${runs_data}|${ratio}"
    done
    echo "Compression Ratio (%)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Add detailed InfluxDB table
    cat >> "${COMPARISON_OUTPUT}" << EOF

========================================
INFLUXDB - Detailed Results (All ${NUM_RUNS} run(s))
========================================

EOF
    
    # Build InfluxDB table header (same structure)
    echo "$ch_header" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %12s", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Print separator
    printf '%s\n' "$(head -c $col_width < /dev/zero | tr '\0' '=')" >> "${COMPARISON_OUTPUT}"
    
    # Print InfluxDB data
    # Row 1: Ingestion Time
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${run}p" "${OUTPUT_DIR}/influx_ingest_times.txt")
        runs_data="${runs_data}|${time}"
    done
    echo "Ingestion Time (ms)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 2: Pre-compaction Storage (convert Bytes to MB)
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        bytes=$(sed -n "${run}p" "${OUTPUT_DIR}/influx_pre_storage.txt")
        mb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1048576}")
        runs_data="${runs_data}|${mb}"
    done
    echo "Pre-compaction Storage (MB)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 3: Compaction Time
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        time=$(sed -n "${run}p" "${OUTPUT_DIR}/influx_compact_times.txt")
        runs_data="${runs_data}|${time}"
    done
    echo "Compaction Time (ms)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 4: Post-compaction Storage (convert Bytes to MB)
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        bytes=$(sed -n "${run}p" "${OUTPUT_DIR}/influx_post_storage.txt")
        mb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1048576}")
        runs_data="${runs_data}|${mb}"
    done
    echo "Post-compaction Storage (MB)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Row 5: Compression Ratio
    runs_data=""
    for run in $(seq 1 ${NUM_RUNS}); do
        ratio=$(sed -n "${run}p" "${OUTPUT_DIR}/influx_compression.txt")
        runs_data="${runs_data}|${ratio}"
    done
    echo "Compression Ratio (%)${runs_data}" | awk -F'|' '{
        printf "%-45s", $1
        for(i=2; i<=NF; i++) printf " | %10.2f", $i
        print ""
    }' >> "${COMPARISON_OUTPUT}"
    
    # Add summary
    cat >> "${COMPARISON_OUTPUT}" << EOF

========================================
SUMMARY
========================================

Total metrics compared: 5
ClickHouse wins: ${ch_wins}
InfluxDB wins: ${influx_wins}

Average performance:
  ClickHouse: Ingestion ${ch_avg_ingest} ms, Storage ${ch_avg_post} MB, Compression ${ch_avg_compression}%
  InfluxDB:   Ingestion ${influx_avg_ingest} ms, Storage ${influx_avg_post} MB, Compression ${influx_avg_compression}%

EOF
    
    # Overall winner (based on ingestion time as primary metric)
    if (( $(awk "BEGIN {print ($ch_avg_ingest < $influx_avg_ingest)}") )); then
        overall_speedup=$(awk "BEGIN {printf \"%.2f\", $influx_avg_ingest / $ch_avg_ingest}")
        overall_pct=$(awk "BEGIN {printf \"%.1f\", ($influx_avg_ingest - $ch_avg_ingest) / $influx_avg_ingest * 100}")
        echo "Overall Winner: ClickHouse (${overall_speedup}x faster ingestion, ${overall_pct}% improvement)" >> "${COMPARISON_OUTPUT}"
    else
        overall_speedup=$(awk "BEGIN {printf \"%.2f\", $ch_avg_ingest / $influx_avg_ingest}")
        overall_pct=$(awk "BEGIN {printf \"%.1f\", ($ch_avg_ingest - $influx_avg_ingest) / $ch_avg_ingest * 100}")
        echo "Overall Winner: InfluxDB (${overall_speedup}x faster ingestion, ${overall_pct}% improvement)" >> "${COMPARISON_OUTPUT}"
    fi
    
    echo "========================================" >> "${COMPARISON_OUTPUT}"
    
    # Cleanup temp files
    rm -f "${OUTPUT_DIR}"/ch_*.txt "${OUTPUT_DIR}"/influx_*.txt
    
    print_banner "Benchmark Complete!"
    
    echo "Results saved to: ${COMPARISON_OUTPUT}"
    echo ""
    echo -e "${BOLD}Summary:${NC}"
    echo "  Total metrics compared: 5"
    echo "  ClickHouse wins: ${ch_wins}"
    echo "  InfluxDB wins: ${influx_wins}"
    echo "  Average ingestion: ClickHouse ${ch_avg_ingest} ms vs InfluxDB ${influx_avg_ingest} ms"
    echo "  Average compression: ClickHouse ${ch_avg_compression}% vs InfluxDB ${influx_avg_compression}%"
    echo ""
    if (( $(awk "BEGIN {print ($ch_avg_ingest < $influx_avg_ingest)}") )); then
        echo -e "  ${GREEN}Winner: ClickHouse (${overall_speedup}x faster)${NC}"
    else
        echo -e "  ${GREEN}Winner: InfluxDB (${overall_speedup}x faster)${NC}"
    fi
    echo ""
    echo "View results:"
    echo "  cat ${COMPARISON_OUTPUT}"
    echo ""
}

# ============================================================================
# Script Entry Point
# ============================================================================

# Verify required files exist
if [ ! -f "${SETUP_SCRIPT}" ]; then
    print_error "Setup script not found: ${SETUP_SCRIPT}"
    exit 1
fi

if [ ! -f "${INGEST_CH_SCRIPT}" ]; then
    print_error "ClickHouse ingest script not found: ${INGEST_CH_SCRIPT}"
    exit 1
fi

if [ ! -f "${INGEST_INFLUX_SCRIPT}" ]; then
    print_error "InfluxDB ingest script not found: ${INGEST_INFLUX_SCRIPT}"
    exit 1
fi

if [ ! -f "${DOCKER_DIR}/docker-compose.yml" ]; then
    print_error "Docker Compose file not found: ${DOCKER_DIR}/docker-compose.yml"
    exit 1
fi

# Run main function
main

exit 0

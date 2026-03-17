#!/bin/bash
# Concise benchmark: ClickHouse vs InfluxDB cardinality comparison
# Tests 2 cardinality levels to demonstrate performance differences
#
# Test cases:
#   Level 1: 100 src IPs × 100 dst IPs  (~15K series)  - baseline
#   Level 2: 200 src IPs × 200 dst IPs  (~60K series)  - moderate load
#
# Workflow per test:
#   1. Generate synthetic NetFlow data
#   2. Benchmark ClickHouse ingestion
#   3. Benchmark InfluxDB ingestion  
#   4. Clean up data files
#   5. Repeat for next level

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
DATA_GEN_DIR="${PROJECT_ROOT}/data-gen"
OUTPUT_DIR="${DATA_GEN_DIR}/output"
INGESTION_DIR="${PROJECT_ROOT}/scripts/ingestion"
RESULTS_DIR="${PROJECT_ROOT}/benchmark-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="${RESULTS_DIR}/benchmark_${TIMESTAMP}.csv"

# Test configurations: level:records:src_ips:dst_ips:days
declare -a TESTS=(
    "low:10000:10:10:7"
    #"medium:4000000:200:200:14"
)


# ============================================================================
# SETUP
# ============================================================================

setup() {
    mkdir -p "$RESULTS_DIR"
    
    # Verify prerequisites
    command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required"; exit 1; }
    docker ps >/dev/null 2>&1 || { echo "ERROR: Docker not running"; exit 1; }
    docker ps | grep -q clickhouse01 || { echo "ERROR: ClickHouse not running"; exit 1; }
    docker ps | grep -q influxdb || { echo "ERROR: InfluxDB not running"; exit 1; }
    
    # CSV header
    echo "Level,Records,Src_IPs,Dst_IPs,Data_MB,CH_Time_s,CH_Rows,CH_Rate,Influx_Time_s,Influx_Rate,Speedup" > "$CSV_FILE"
    
    echo "Benchmark started: $(date)"
    echo "Results file: $CSV_FILE"
    echo ""
}

# ============================================================================
# DATA GENERATION
# ============================================================================

generate_data() {
    local level=$1 records=$2 src_ips=$3 dst_ips=$4 days=$5
    
    # Clean previous data
    rm -rf "${OUTPUT_DIR:?}"/*
    
    cd "$DATA_GEN_DIR"
    
    # Generate NetFlow data
    # Monitor: Generation speed should be 200K-500K rows/sec
    # Watch CPU usage (should be near 100% on one core)
    python3 generate_flows.py \
        --records "$records" \
        --unique-src-ips "$src_ips" \
        --unique-dst-ips "$dst_ips" \
        --time-range-days "$days" \
        --output output/ 2>&1 | grep -E "(Generating|Complete|records/sec)" || true
    
    # Calculate data size
    local data_mb=$(du -sm "$OUTPUT_DIR" | cut -f1)
    
    cd "$SCRIPT_DIR"
    echo "$data_mb"
}

# ============================================================================
# CLICKHOUSE BENCHMARK
# ============================================================================

benchmark_clickhouse() {
    local level=$1
    
    # Clean table
    docker exec -i clickhouse01 clickhouse-client \
        --query "TRUNCATE TABLE IF EXISTS netflow.flows_local" 2>&1 | grep -v "^$" || true
    
    cd "$INGESTION_DIR"
    
    # Run ingestion
    # Monitor: docker exec -i clickhouse01 clickhouse-client --query "SELECT count() FROM netflow.flows_local"
    # Watch: INSERT throughput, memory usage (should stay low)
    local start_time=$(date +%s)
    bash ingest_clickhouse.sh "$OUTPUT_DIR" 2>&1 | grep -E "(Processing|Complete|rows/s)" || true
    local end_time=$(date +%s)
    
    local elapsed=$((end_time - start_time))
    
    # Get final row count
    local row_count=$(docker exec -i clickhouse01 clickhouse-client \
        --query "SELECT count() FROM netflow.flows_local" 2>/dev/null)
    
    local rate=0
    if [ $elapsed -gt 0 ]; then
        rate=$((row_count / elapsed))
    fi
    
    cd "$SCRIPT_DIR"
    echo "${elapsed}:${row_count}:${rate}"
}

# ============================================================================
# INFLUXDB BENCHMARK  
# ============================================================================

benchmark_influxdb() {
    local level=$1 records=$2
    
    # Recreate bucket (clean slate)
    docker exec influxdb influx bucket delete \
        --name flows \
        --org netflow \
        --token my-super-secret-auth-token 2>/dev/null || true
    
    docker exec influxdb influx bucket create \
        --name flows \
        --org netflow \
        --retention 30d \
        --token my-super-secret-auth-token 2>&1 | grep -v "^$" || true
    
    cd "$INGESTION_DIR"
    
    # Run ingestion
    # Monitor: docker logs influxdb --tail 50 (watch for TSI index messages, write performance)
    # Watch: Memory usage (InfluxDB process), series cardinality growth
    # Expected: May see slowdown as cardinality increases
    local start_time=$(date +%s)
    bash ingest_influxdb.sh "$OUTPUT_DIR" 2>&1 | grep -E "(Processing|Complete|rows/s)" || true
    local end_time=$(date +%s)
    
    local elapsed=$((end_time - start_time))
    
    local rate=0
    if [ $elapsed -gt 0 ]; then
        rate=$((records / elapsed))
    fi
    
    cd "$SCRIPT_DIR"
    echo "${elapsed}:${rate}"
}

# ============================================================================
# MAIN BENCHMARK LOOP
# ============================================================================

run_benchmarks() {
    local test_num=1
    
    for test_config in "${TESTS[@]}"; do
        IFS=':' read -r level records src_ips dst_ips days <<< "$test_config"
        
        echo "=========================================="
        echo "Test $test_num: $level"
        echo "  Config: ${records} records, ${src_ips} src IPs, ${dst_ips} dst IPs"
        echo "=========================================="
        
        # Step 1: Generate data
        echo "[1/4] Generating data..."
        data_mb=$(generate_data "$level" "$records" "$src_ips" "$dst_ips" "$days")
        echo "  Generated ${data_mb} MB"
        
        # Step 2: Benchmark ClickHouse
        echo "[2/4] Benchmarking ClickHouse..."
        ch_result=$(benchmark_clickhouse "$level")
        IFS=':' read -r ch_time ch_rows ch_rate <<< "$ch_result"
        printf "  Time: %ss, Rows: %s, Rate: %s rows/s\n" "$ch_time" "$ch_rows" "$ch_rate"
        
        # Step 3: Benchmark InfluxDB
        echo "[3/4] Benchmarking InfluxDB..."
        influx_result=$(benchmark_influxdb "$level" "$records")
        IFS=':' read -r influx_time influx_rate <<< "$influx_result"
        printf "  Time: %ss, Rate: %s rows/s\n" "$influx_time" "$influx_rate"
        
        # Calculate speedup
        local speedup="N/A"
        if [ $ch_time -gt 0 ]; then
            speedup=$(echo "scale=2; $influx_time / $ch_time" | bc)
        fi
        
        # Step 4: Save results and cleanup
        echo "[4/4] Saving results and cleaning up..."
        echo "$level,$records,$src_ips,$dst_ips,$data_mb,$ch_time,$ch_rows,$ch_rate,$influx_time,$influx_rate,$speedup" >> "$CSV_FILE"
        rm -rf "${OUTPUT_DIR:?}"/*
        
        echo "  Speedup: ${speedup}x (ClickHouse vs InfluxDB)"
        echo "  Completed: $level"
        echo ""
        
        test_num=$((test_num + 1))
    done
}

# ============================================================================
# FINAL REPORT
# ============================================================================

generate_report() {
    echo "=========================================="
    echo "Benchmark Complete"
    echo "=========================================="
    echo ""
    echo "Results saved to: $CSV_FILE"
    echo ""
    echo "Summary:"
    tail -n +2 "$CSV_FILE" | while IFS=',' read -r level records src dst mb ch_time ch_rows ch_rate influx_time influx_rate speedup; do
        printf "  %-10s: ClickHouse %4ss (%s rows/s) | InfluxDB %4ss (%s rows/s) | %sx speedup\n" \
            "$level" "$ch_time" "$ch_rate" "$influx_time" "$influx_rate" "$speedup"
    done
    echo ""
    echo "Import CSV for visualization:"
    echo "  python3: pandas.read_csv('$CSV_FILE')"
    echo "  R: read.csv('$CSV_FILE')"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    setup
    run_benchmarks
    generate_report
}

# Run benchmark
main "$@"

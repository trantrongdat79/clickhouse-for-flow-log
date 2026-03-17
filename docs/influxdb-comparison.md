# InfluxDB Comparison - Quick Reference

## 🎯 Goal
Demonstrate that **ClickHouse is superior for high-cardinality NetFlow data** by comparing against InfluxDB, showing ClickHouse's advantages in ingestion speed, query performance, and storage efficiency.

---

## 📦 What to Implement

### 1. Data Conversion Script
**File**: `data-gen/convert_to_influxdb.py`
- Converts NetFlow JSONEachRow → InfluxDB Line Protocol
- Each flow becomes 1 measurement with multiple tags and fields
- **Challenge**: High-cardinality tags (src_ip × dst_ip = millions of series)

### 2. Ingestion Script
**File**: `scripts/ingestion/ingest_influxdb.sh`
- Automates conversion + push to InfluxDB API
- Monitors InfluxDB metrics before/after
- Shows memory usage, series count, timing

### 3. Infrastructure Setup
**File**: `docker/docker-compose.yml`
- Add InfluxDB 2.x service (port 8086)
- Configure memory limits to observe resource usage
- Set up bucket and organization

### 4. Automated Comparison
**File**: `scripts/benchmark/compare_performance.sh`
- Runs identical datasets through both systems
- Measures time, memory, throughput
- Generates comparison report

---

## 🚀 Quick Start

### Step 1: Start Infrastructure
```bash
cd docker
docker-compose up -d influxdb clickhouse01

# Wait for healthy status
docker ps
```

### Step 2: Run Small Test (1K records)
```bash
cd ../scripts/ingestion

# Generate 1K records
python3 ../../data-gen/generate_flows.py \
  --records 1000 \
  --output ../../data-gen/output_test/

# Ingest to InfluxDB
./ingest_influxdb.sh ../../data-gen/output_test/flows_001.json 1000

# Ingest to ClickHouse (for comparison)
./ingest_clickhouse.sh ../../data-gen/output_test/flows_001.json
```

**Expected Result**: Both work fine, ClickHouse ~5-10x faster

### Step 3: Scale Up (50K records)
```bash
# Generate 50K
python3 ../../data-gen/generate_flows.py \
  --records 50000 \
  --unique-src-ips 5000 \
  --unique-dst-ips 20000 \
  --output ../../data-gen/output_test/

# Ingest to both systems
./ingest_influxdb.sh ../../data-gen/output_test/flows_001.json 50000
./ingest_clickhouse.sh ../../data-gen/output_test/flows_001.json
```

**Expected Result**: ClickHouse 10-20x faster, lower memory usage

### Step 4: Push to Recommended Scale (10M records)
```bash
# Generate 10M
python3 ../../data-gen/generate_flows.py \
  --records 10000000 \
  --unique-src-ips 10000 \
  --unique-dst-ips 50000 \
  --output ../../data-gen/output_10m/

# Ingest to both (InfluxDB will struggle)
./ingest_influxdb.sh ../../data-gen/output_10m/flows_001.json
./ingest_clickhouse.sh ../../data-gen/output_10m/flows_001.json
```

**Expected Result**: 
- ClickHouse: Fast ingestion, efficient storage
- InfluxDB: Much slower, higher memory, may show cardinality warnings

### Step 5: Automated Comparison
```bash
cd ../benchmark
./compare_performance.sh
```

This runs progressive tests (1K → 10K → 100K → 1M) and generates comparison report.

---

## 📊 What to Observe

### Ingestion Performance

**Metrics to Track**:
- **Time**: Wall-clock duration (start to finish)
- **Throughput**: Records per second
- **Memory**: Peak memory usage during ingestion
- **CPU**: Average CPU utilization

**Expected Results** (10M records):

| Metric | ClickHouse | InfluxDB 2.x | Ratio |
|--------|------------|--------------|-------|
| **Duration** | 3-5 min | 15-25 min | **3-5x faster** |
| **Throughput** | 50-70K rows/sec | 10-15K rows/sec | **4-5x higher** |
| **Memory Peak** | 2-3 GB | 5-8 GB | **2-3x lower** |
| **CPU Average** | 60-70% | 80-95% | More efficient |

### Query Performance

**Test Queries**:

#### Q1: High-Cardinality Aggregation (Top Talkers)

**ClickHouse**:
```sql
SELECT 
    IPv4NumToString(src_ip) as source,
    count() as flows,
    formatReadableSize(sum(bytes)) as traffic
FROM netflow.flows_local
GROUP BY src_ip
ORDER BY sum(bytes) DESC
LIMIT 100;
```
**Expected**: ~0.5-1 second

**InfluxDB (Flux)**:
```flux
from(bucket: "netflow")
  |> range(start: -30d)
  |> filter(fn: (r) => r._measurement == "flow")
  |> group(columns: ["src_ip"])
  |> sum(column: "_value")
  |> top(n: 100, columns: ["_value"])
```
**Expected**: 5-15 seconds (10-20x slower)

---

#### Q2: Multi-Dimensional Analysis

**ClickHouse**:
```sql
SELECT 
    toHour(timestamp) as hour,
    protocol_name,
    dst_port,
    count() as flows,
    avg(bytes) as avg_bytes
FROM netflow.flows_local
WHERE timestamp >= now() - INTERVAL 7 DAY
GROUP BY hour, protocol_name, dst_port
HAVING flows > 100
ORDER BY hour, flows DESC;
```
**Expected**: ~1-2 seconds

**InfluxDB (Flux)**:
```flux
from(bucket: "netflow")
  |> range(start: -7d)
  |> filter(fn: (r) => r._measurement == "flow")
  |> group(columns: ["hour", "protocol", "dst_port"])
  |> aggregateWindow(every: 1h, fn: mean)
  |> filter(fn: (r) => r.flows > 100)
```
**Expected**: 10-30 seconds or timeout

---

#### Q3: Percentile Calculations

**ClickHouse**:
```sql
SELECT 
    protocol_name,
    quantile(0.5)(bytes) as median,
    quantile(0.95)(bytes) as p95,
    quantile(0.99)(bytes) as p99
FROM netflow.flows_local
GROUP BY protocol_name;
```
**Expected**: ~0.5-1 second (exact percentiles)

**InfluxDB (Flux)**:
```flux
from(bucket: "netflow")
  |> range(start: -30d)
  |> filter(fn: (r) => r._measurement == "flow" and r._field == "bytes")
  |> group(columns: ["protocol"])
  |> quantile(q: 0.95, method: "estimate_tdigest")
```
**Expected**: 5-10 seconds (approximate percentiles)

---

### Storage Efficiency

**Check ClickHouse Storage**:
```sql
SELECT 
    formatReadableSize(sum(bytes_on_disk)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size,
    round(sum(data_uncompressed_bytes) / sum(bytes_on_disk), 2) as compression_ratio
FROM system.parts
WHERE database = 'netflow' AND table = 'flows_local' AND active;
```

**Check InfluxDB Storage**:
```bash
# Via InfluxDB API
curl -s "http://localhost:8086/api/v2/buckets" \
  -H "Authorization: Token YOUR_TOKEN" | \
  jq '.buckets[] | select(.name=="netflow") | .retentionRules'

# Disk usage
docker exec influxdb du -sh /var/lib/influxdb2
```

**Expected Results** (10M records):

| Metric | ClickHouse | InfluxDB | Ratio |
|--------|------------|----------|-------|
| Raw Size | ~3 GB | ~3 GB | 1x |
| Compressed | ~400 MB | ~1.2 GB | **3x smaller** |
| Compression Ratio | 7-8x | 2.5-3x | **2-3x better** |

---

## 🏗️ Implementation Guide

### 1. InfluxDB Setup in Docker Compose

Add to `docker/docker-compose.yml`:

```yaml
services:
  influxdb:
    image: influxdb:2.7
    container_name: influxdb
    ports:
      - "8086:8086"
    environment:
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: admin
      DOCKER_INFLUXDB_INIT_PASSWORD: ${INFLUXDB_ADMIN_PASSWORD}
      DOCKER_INFLUXDB_INIT_ORG: ${INFLUXDB_ORG:-netflow_org}
      DOCKER_INFLUXDB_INIT_BUCKET: ${INFLUXDB_BUCKET:-netflow}
      DOCKER_INFLUXDB_INIT_RETENTION: ${INFLUXDB_RETENTION:-30d}
      DOCKER_INFLUXDB_INIT_ADMIN_TOKEN: ${INFLUXDB_TOKEN:-my-super-secret-auth-token}
    volumes:
      - influxdb_data:/var/lib/influxdb2
    networks:
      - clickhouse_network
    restart: unless-stopped

volumes:
  influxdb_data:
```

Add to `docker/.env`:
```bash
# InfluxDB Configuration
INFLUXDB_ORG=netflow_org
INFLUXDB_BUCKET=netflow
INFLUXDB_RETENTION=30d
INFLUXDB_ADMIN_PASSWORD=admin_password
INFLUXDB_TOKEN=my-super-secret-auth-token
```

---

### 2. Data Conversion Script

**File**: `data-gen/convert_to_influxdb.py`

```python
#!/usr/bin/env python3
"""
Convert NetFlow JSONEachRow to InfluxDB Line Protocol
Demonstrates high-cardinality challenge with InfluxDB tags
"""

import json
import sys
from datetime import datetime
from pathlib import Path

def convert_flow_to_line_protocol(flow):
    """
    Convert single flow record to InfluxDB Line Protocol
    
    Format: measurement,tag1=value1,tag2=value2 field1=value1,field2=value2 timestamp
    
    Tags (indexed, creates cardinality):
        - src_ip, dst_ip, protocol, src_port, dst_port
        - Each unique combination = new series
    
    Fields (not indexed, numeric values):
        - bytes, packets, duration
    """
    # Measurement name
    measurement = "flow"
    
    # Tags (high cardinality!)
    tags = [
        f"src_ip={flow['src_ip']}",
        f"dst_ip={flow['dst_ip']}",
        f"protocol={flow.get('protocol_name', 'TCP')}",
        f"src_port={flow['src_port']}",
        f"dst_port={flow['dst_port']}"
    ]
    
    # Optional: Add geo tags (further increases cardinality)
    if 'src_geo_latitude' in flow:
        tags.append(f"src_geo_lat={flow['src_geo_latitude']:.2f}")
        tags.append(f"src_geo_lon={flow['src_geo_longitude']:.2f}")
    
    tag_str = ",".join(tags)
    
    # Fields (actual measurements)
    fields = [
        f"bytes={int(flow['bytes'])}i",
        f"packets={int(flow['packets'])}i",
        f"duration={float(flow['flow_duration'])}"
    ]
    field_str = ",".join(fields)
    
    # Timestamp (nanoseconds since epoch)
    if isinstance(flow['timestamp'], str):
        dt = datetime.fromisoformat(flow['timestamp'].replace(' ', 'T'))
    else:
        dt = flow['timestamp']
    timestamp_ns = int(dt.timestamp() * 1e9)
    
    # Line Protocol format
    return f"{measurement},{tag_str} {field_str} {timestamp_ns}"

def convert_file(input_file, output_file, max_records=None):
    """Convert JSONEachRow file to Line Protocol format"""
    
    records_processed = 0
    unique_series = set()
    
    with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
        for line in infile:
            if max_records and records_processed >= max_records:
                break
            
            flow = json.loads(line.strip())
            line_protocol = convert_flow_to_line_protocol(flow)
            outfile.write(line_protocol + '\n')
            
            # Track unique series (for reporting)
            series_key = line_protocol.split(' ')[0]  # measurement + tags
            unique_series.add(series_key)
            
            records_processed += 1
            
            if records_processed % 10000 == 0:
                print(f"Processed {records_processed:,} records, "
                      f"{len(unique_series):,} unique series...", 
                      file=sys.stderr)
    
    return records_processed, len(unique_series)

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', help='Input JSONEachRow file')
    parser.add_argument('output', help='Output Line Protocol file')
    parser.add_argument('--max-records', type=int, 
                        help='Maximum records to convert (for testing)')
    
    args = parser.parse_args()
    
    print(f"Converting {args.input} to InfluxDB Line Protocol...", file=sys.stderr)
    
    records, series = convert_file(args.input, args.output, args.max_records)
    
    print(f"\nConversion complete:", file=sys.stderr)
    print(f"  Records processed: {records:,}", file=sys.stderr)
    print(f"  Unique time series: {series:,}", file=sys.stderr)
    print(f"  Output file: {args.output}", file=sys.stderr)
    print(f"\n⚠️  WARNING: {series:,} unique series created!", file=sys.stderr)
    print(f"  InfluxDB recommended limit: ~1,000,000 series", file=sys.stderr)
    
    if series > 100000:
        print(f"\n⚠️  High cardinality detected! InfluxDB may struggle.", file=sys.stderr)

if __name__ == '__main__':
    main()
```

---

### 3. Ingestion Script for InfluxDB

**File**: `scripts/ingestion/ingest_influxdb.sh`

```bash
#!/bin/bash
# Script: ingest_influxdb.sh
# Purpose: Ingest NetFlow data into InfluxDB via Line Protocol
# Usage: ./ingest_influxdb.sh <json_file> [max_records]

set -euo pipefail

# Configuration
INFLUXDB_HOST="${INFLUXDB_HOST:-localhost}"
INFLUXDB_PORT="${INFLUXDB_PORT:-8086}"
INFLUXDB_ORG="${INFLUXDB_ORG:-netflow_org}"
INFLUXDB_BUCKET="${INFLUXDB_BUCKET:-netflow}"
INFLUXDB_TOKEN="${INFLUXDB_TOKEN:-my-super-secret-auth-token}"

INPUT_FILE="$1"
MAX_RECORDS="${2:-}"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

echo "=== InfluxDB Ingestion ==="
echo "Input: $INPUT_FILE"
echo "Max records: ${MAX_RECORDS:-all}"
echo ""

# Convert to Line Protocol
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo "Step 1: Converting to Line Protocol..."
if [[ -n "$MAX_RECORDS" ]]; then
    python3 ../../data-gen/convert_to_influxdb.py \
        "$INPUT_FILE" "$TEMP_FILE" --max-records "$MAX_RECORDS"
else
    python3 ../../data-gen/convert_to_influxdb.py \
        "$INPUT_FILE" "$TEMP_FILE"
fi

echo ""
echo "Step 2: Writing to InfluxDB..."

# Get metrics before ingestion
SERIES_BEFORE=$(curl -s "http://${INFLUXDB_HOST}:${INFLUXDB_PORT}/api/v2/query" \
    -H "Authorization: Token ${INFLUXDB_TOKEN}" \
    -H "Content-Type: application/vnd.flux" \
    -d "from(bucket:\"${INFLUXDB_BUCKET}\") |> range(start: -30d) |> group() |> count()" \
    2>/dev/null | grep -oP '"_value":\K\d+' | head -1 || echo "0")

# Time the ingestion
START_TIME=$(date +%s)

# Write data using InfluxDB write API
cat "$TEMP_FILE" | curl -s -XPOST \
    "http://${INFLUXDB_HOST}:${INFLUXDB_PORT}/api/v2/write?org=${INFLUXDB_ORG}&bucket=${INFLUXDB_BUCKET}&precision=ns" \
    -H "Authorization: Token ${INFLUXDB_TOKEN}" \
    -H "Content-Type: text/plain; charset=utf-8" \
    --data-binary @-

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Get metrics after ingestion
sleep 2  # Wait for InfluxDB to process
SERIES_AFTER=$(curl -s "http://${INFLUXDB_HOST}:${INFLUXDB_PORT}/api/v2/query" \
    -H "Authorization: Token ${INFLUXDB_TOKEN}" \
    -H "Content-Type: application/vnd.flux" \
    -d "from(bucket:\"${INFLUXDB_BUCKET}\") |> range(start: -30d) |> group() |> count()" \
    2>/dev/null | grep -oP '"_value":\K\d+' | head -1 || echo "0")

SERIES_ADDED=$((SERIES_AFTER - SERIES_BEFORE))

echo ""
echo "=== Ingestion Complete ==="
echo "Duration: ${DURATION}s"
echo "Series before: ${SERIES_BEFORE}"
echo "Series after: ${SERIES_AFTER}"
echo "Series added: ${SERIES_ADDED}"

# Check memory usage
echo ""
echo "=== Resource Usage ==="
docker stats influxdb --no-stream --format "Memory: {{.MemUsage}}"

echo ""
echo "✓ InfluxDB ingestion complete"
```

---

### 4. Comparison Script

**File**: `scripts/benchmark/compare_performance.sh`

```bash
#!/bin/bash
# Script: compare_performance.sh
# Purpose: Compare ClickHouse vs InfluxDB ingestion and query performance

set -euo pipefail

echo "=== ClickHouse vs InfluxDB Performance Comparison ==="
echo ""

# Test datasets
DATASETS=(
    "1000:1K records"
    "10000:10K records"
    "100000:100K records"
    "1000000:1M records"
)

RESULTS_FILE="../../benchmark-results/comparison_$(date +%Y%m%d_%H%M%S).csv"

# CSV header
echo "Dataset,System,Duration(s),Throughput(rows/sec),Memory(MB)" > "$RESULTS_FILE"

for dataset in "${DATASETS[@]}"; do
    RECORDS="${dataset%%:*}"
    DESC="${dataset##*:}"
    
    echo "Testing with $DESC..."
    
    # Generate data
    echo "  Generating data..."
    python3 ../../data-gen/generate_flows.py \
        --records "$RECORDS" \
        --output "../../data-gen/output_test_${RECORDS}/" \
        --quiet
    
    TEST_FILE="../../data-gen/output_test_${RECORDS}/flows_001.json"
    
    # Test ClickHouse
    echo "  Testing ClickHouse..."
    CH_START=$(date +%s)
    docker cp "$TEST_FILE" clickhouse01:/tmp/flows.json
    docker exec clickhouse01 sh -c \
        "cat /tmp/flows.json | clickhouse-client --password admin \
         --query 'INSERT INTO netflow.flows_local FORMAT JSONEachRow'" \
        2>/dev/null
    CH_END=$(date +%s)
    CH_DURATION=$((CH_END - CH_START))
    CH_THROUGHPUT=$((RECORDS / CH_DURATION))
    CH_MEMORY=$(docker stats clickhouse01 --no-stream --format "{{.MemUsage}}" | \
                grep -oP '\d+\.\d+MiB' | grep -oP '\d+\.\d+' || echo "0")
    
    echo "$DESC,ClickHouse,$CH_DURATION,$CH_THROUGHPUT,$CH_MEMORY" >> "$RESULTS_FILE"
    
    # Test InfluxDB
    echo "  Testing InfluxDB..."
    IDB_START=$(date +%s)
    cd ../ingestion
    ./ingest_influxdb.sh "$TEST_FILE" "$RECORDS" > /dev/null 2>&1
    cd ../benchmark
    IDB_END=$(date +%s)
    IDB_DURATION=$((IDB_END - IDB_START))
    IDB_THROUGHPUT=$((RECORDS / IDB_DURATION))
    IDB_MEMORY=$(docker stats influxdb --no-stream --format "{{.MemUsage}}" | \
                 grep -oP '\d+\.\d+MiB' | grep -oP '\d+\.\d+' || echo "0")
    
    echo "$DESC,InfluxDB,$IDB_DURATION,$IDB_THROUGHPUT,$IDB_MEMORY" >> "$RESULTS_FILE"
    
    echo "  ClickHouse: ${CH_DURATION}s (${CH_THROUGHPUT} rows/sec)"
    echo "  InfluxDB:   ${IDB_DURATION}s (${IDB_THROUGHPUT} rows/sec)"
    echo ""
done

echo "=== Comparison Complete ==="
echo "Results saved to: $RESULTS_FILE"
echo ""
cat "$RESULTS_FILE"
```

---

## 🔍 Why InfluxDB Struggles

### Architectural Differences

| Aspect | ClickHouse | InfluxDB 2.x |
|--------|------------|--------------|
| **Storage Model** | Columnar (all fields treated equally) | Tag/Field separation |
| **Indexing** | Primary key + skip indexes | Tags fully indexed |
| **Cardinality** | Unlimited | ~1M series recommended |
| **Compression** | Codec per column (Delta, Gorilla, etc.) | Snappy/Zstd (generic) |
| **Query Model** | SQL-like | Flux (functional) |

### High-Cardinality Impact

**NetFlow Cardinality Calculation**:
```
Unique combinations = src_IPs × dst_IPs × src_ports × dst_ports × protocols
                   = 50,000 × 200,000 × 65,536 × 65,536 × 3
                   = ~2.5 × 10^20 potential series
```

**InfluxDB Problem**:
- Each unique tag combination = new series
- Series metadata stored in memory
- Recommended limit: ~1M active series
- High cardinality = memory explosion + slow queries

**ClickHouse Solution**:
- No concept of "series"
- All columns treated as data
- Bloom filters handle high-cardinality lookups
- No memory penalty for cardinality

---

## 📈 Demonstration Strategy

### For Academic Project

**Recommended Approach**:
1. **Start small** (1K records): Show both work
2. **Scale up** (50K records): Show ClickHouse faster
3. **Push limits** (10M records): Show InfluxDB struggles significantly
4. **Document** (report): Explain architectural reasons

**Key Points to Demonstrate**:
1. **Ingestion**: ClickHouse 3-5x faster
2. **Queries**: ClickHouse 10-20x faster on high-cardinality
3. **Storage**: ClickHouse 2-3x more efficient compression
4. **Scalability**: ClickHouse handles unlimited cardinality

### For Presentation

**Talking Points**:
- "InfluxDB designed for low-cardinality metrics (Kubernetes pods, servers)"
- "NetFlow has extreme cardinality (millions of IP combinations)"
- "ClickHouse handles this naturally with columnar storage"
- "Result: ClickHouse is the right tool for this workload"

---

## ⚙️ Configuration Best Practices

### InfluxDB Memory Limits

To observe resource constraints:

```yaml
# docker-compose.yml
services:
  influxdb:
    # ... other config ...
    deploy:
      resources:
        limits:
          memory: 8G  # Set limit to observe memory pressure
```

### Monitoring InfluxDB Health

```bash
# Check series cardinality
curl -s "http://localhost:8086/api/v2/query" \
  -H "Authorization: Token ${INFLUXDB_TOKEN}" \
  -d 'from(bucket:"netflow") |> range(start: -30d) |> group() |> count()'

# Check bucket stats
curl "http://localhost:8086/api/v2/buckets" \
  -H "Authorization: Token ${INFLUXDB_TOKEN}"

# Monitor logs for cardinality warnings
docker logs influxdb | grep -i cardinality
```

---

## 🎓 Lessons Learned

### When to Use InfluxDB
✅ **Good For**:
- Low-cardinality time-series (server metrics, application metrics)
- Real-time alerting
- Retention policies with automatic downsampling
- Prometheus-style metrics collection

### When to Use ClickHouse
✅ **Betterfor**:
- High-cardinality data (NetFlow, logs, events)
- Complex analytical queries
- Large-scale data warehousing
- Historical analysis and reporting

### Key Takeaway
> **"Use the right tool for the job"**  
> InfluxDB excellent for metrics, ClickHouse superior for analytics

---

**Document Version**: 1.0  
**Last Updated**: 2026-03-16  
**Status**: Ready for Implementation

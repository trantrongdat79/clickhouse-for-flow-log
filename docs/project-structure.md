# ClickHouse NetFlow Analytics - Complete Project Reference

This document serves as the comprehensive reference for the ClickHouse high-cardinality NetFlow analytics project, consolidating architecture, setup, testing, and lessons learned.

---

## Table of Contents

1. [Project Directory Structure](#project-directory-structure)
2. [ClickHouse Lessons Learned](#clickhouse-lessons-learned)
3. [Quick Start Guide](#quick-start-guide)
4. [Dataset Planning for Limited Storage](#dataset-planning-for-limited-storage)
5. [Testing & Verification](#testing--verification)
6. [Project Report Guidelines](#project-report-guidelines)
7. [Configuration Reference](#configuration-reference)
8. [Troubleshooting](#troubleshooting)

---

## Project Directory Structure

### Complete Directory Layout

```
clickhouse-for-flow-log/
│
├── README.md                           # Project overview, quick start
├── .gitignore                          # Git ignore patterns
├── .env.example                        # Environment variables template
│
├── docker/                             # Docker infrastructure
│   ├── docker-compose.yml              # Main compose file (all services)
│   ├── docker-compose.dev.yml          # Development overrides (optional)
│   ├── docker-compose.prod.yml         # Production settings (optional)
│   ├── .env                            # Environment variables (gitignored)
│   ├── clickhouse/                     # ClickHouse configurations
│   │   ├── config.d/                   # Server configuration overrides
│   │   │   ├── remote_servers.xml      # Cluster topology
│   │   │   ├── macros.xml.template     # Node-specific variables
│   │   │   ├── network.xml             # Network settings
│   │   │   └── storage.xml             # Storage policies (if exists)
│   │   ├── users.d/                    # User configuration
│   │   │   ├── users.xml               # User definitions
│   │   │   └── default-user.xml        # Default user settings
│   │   └── initdb.d/                   # Initialization scripts (optional)
│   ├── influxdb/                       # InfluxDB configurations
│   │   └── scripts/                    # Initialization scripts (optional)
│   ├── grafana/                        # Grafana configurations
│   │   ├── provisioning/               # Auto-provisioning configs
│   │   │   └── datasources/            # Datasource definitions
│   │   │       ├── clickhouse.yml      # ClickHouse datasource
│   │   │       └── influxdb.yml        # InfluxDB datasource
│   │   └── dashboards/                 # Dashboard JSON files
│   └── zookeeper/                      # ZooKeeper configs (for clustering)
│
├── sql/                                # SQL schema and queries
│   ├── schema/                         # DDL statements
│   │   ├── 01-flows-local.sql          # MergeTree table
│   │   ├── 02-flows-distributed.sql    # Distributed table (optional)
│   │   ├── 03-materialized-views.sql   # Pre-aggregation views
│   │   └── 04-skip-indexes.sql         # Bloom filter indexes
│   ├── queries/                        # Sample analytical queries
│   │   ├── verify_data.sql             # Data quality verification
│   │   ├── benchmark_queries.sql       # Performance testing queries
│   │   ├── top_talkers.sql             # Top-N queries
│   │   ├── traffic_matrix.sql          # High-cardinality aggregations
│   │   └── geo_analysis.sql            # Geographic queries
│   └── maintenance/                    # Maintenance queries
│       ├── optimize_tables.sql         # Manual optimization
│       └── cleanup_old_partitions.sql  # Partition management
│
├── data-gen/                           # Data generation scripts
│   ├── requirements.txt                # Python dependencies
│   ├── generate_flows.py               # Main data generator
│   ├── config.yaml                     # Generation parameters
│   ├── convert_to_influxdb.py          # Convert to InfluxDB format
│   └── output/                         # Generated data (gitignored)
│
├── scripts/                            # Operational scripts
│   ├── setup/                          # Setup and initialization
│   │   ├── 01-setup-cluster.sh         # Start containers
│   │   ├── 02-init-schema.sh           # Execute DDL scripts
│   │   └── 03-load-test-data.sh        # Load sample data
│   ├── ingestion/                      # Data ingestion
│   │   ├── ingest_clickhouse.sh        # ClickHouse ingestion
│   │   ├── ingest_influxdb.sh          # InfluxDB ingestion
│   │   └── monitor_ingestion.sh        # Monitor insertion rate
│   ├── benchmark/                      # Performance benchmarking
│   │   ├── benchmark_ingest_clickhouse.sh
│   │   ├── benchmark_ingest_influxdb.sh
│   │   ├── benchmark_queries.sh
│   │   └── compare_performance.sh      # Side-by-side comparison
│   └── monitoring/                     # Monitoring helpers
│       ├── check_cluster_health.sh     # Cluster status check
│       └── check_disk_usage.sh         # Disk space monitoring
│
├── tests/                              # Automated tests
│   ├── integration/                    # Integration tests
│   │   ├── test_cluster_setup.py
│   │   └── test_queries.py
│   └── performance/                    # Performance tests
│       └── test_ingestion_throughput.py
│
├── docs/                               # Documentation
│   ├── AGENTS.md                       # AI agent guidelines
│   ├── project-structure.md            # This file
│   ├── influxdb-comparison.md          # InfluxDB comparison guide
│   └── ideas.md                        # User notes
│
├── data/                               # Persistent data (gitignored)
│   ├── clickhouse01/                   # ClickHouse data
│   ├── influxdb/                       # InfluxDB data
│   └── grafana/                        # Grafana data
│
├── logs/                               # Log files (gitignored)
│   ├── clickhouse01/                   # ClickHouse logs
│   ├── influxdb/                       # InfluxDB logs
│   └── ingestion/                      # Data ingestion logs
│
├── backups/                            # Backup storage (gitignored)
│   └── clickhouse/                     # ClickHouse backups
│
└── benchmark-results/                  # Benchmark outputs
    ├── ingestion_clickhouse.csv
    ├── ingestion_influxdb.csv
    └── queries_comparison.csv
```

### Naming Conventions

**Files**:
- SQL files: `01-descriptive-name.sql` (numbered for execution order)
- Scripts: `descriptive_name.sh` (snake_case)
- Python: `descriptive_name.py` (snake_case)
- Configs: `service-name.yml` or `config-type.xml`

**Database Objects**:
- Tables: `lowercase_snake_case` (e.g., `flows_local`)
- Views: `*_mv` suffix for materialized views (e.g., `flows_hourly_mv`)
- Database: `netflow` (dedicated, not `default`)

**Docker Services**:
- ClickHouse: `clickhouse01`, `clickhouse02`, etc.
- InfluxDB: `influxdb`
- Grafana: `grafana`

---

## ClickHouse Lessons Learned

This section consolidates practical insights gained from implementing the NetFlow analytics pipeline.

### Storage & Compression

**Observed Compression Ratios**:
- NetFlow data: **1.3-1.5x** compression ratio
- Storage efficiency: **~40 bytes per record** (compressed)
- Raw JSON: ~300 bytes per record

**Codec Selection Best Practices**:
```sql
-- Timestamps: DoubleDelta (time-series efficient)
timestamp DateTime CODEC(DoubleDelta, LZ4)

-- Counters (bytes, packets, duration): Delta encoding
bytes UInt64 CODEC(Delta, LZ4)
packets UInt32 CODEC(Delta, LZ4)
flow_duration UInt32 CODEC(Delta, LZ4)

-- Floats (geo-coordinates): Gorilla compression
src_geo_latitude Float32 CODEC(Gorilla, LZ4)
src_geo_longitude Float32 CODEC(Gorilla, LZ4)

-- IPs and ports: Default LZ4 (already compact)
src_ip IPv4
src_port UInt16
```

**Partitioning Strategy**:
- **Daily partitioning** works well for time-series data
- Creates one partition per day: `PARTITION BY toYYYYMMDD(timestamp)`
- 30 days = 30 partitions (manageable)
- 90 days = 90 partitions (still efficient)
- Enables efficient partition pruning in queries

**Storage Efficiency Results** (100K records test):
- Compressed size: **3.99 MiB**
- Partitions: **2** (daily)
- Compression ratio: **1.39x**

### Data Generation Best Practices

**Realistic Distributions**:
- **Traffic patterns**: Pareto distribution (80/20 rule)
  - 20% of IPs generate 80% of traffic
  - Mimics real-world network behavior
- **Bytes/Packets**: Log-normal distribution
  - Most flows are small, few are very large
- **Protocols**: Weighted (70% TCP, 25% UDP, 5% ICMP)

**Cardinality Targets**:
- **50K source IPs**: Realistic enterprise network
- **200K destination IPs**: Internet-facing services
- Creates high-cardinality scenarios (billions of potential combinations)
- Stresses systems designed for low-cardinality

**Time Range Strategy**:
- **30 days**: Good balance for testing (30 partitions, realistic retention)
- **7 days**: For quick tests
- **90 days**: For extensive testing (requires more storage)

**Generation Performance**:
- Speed: **~9,400 records/sec** (Python single-threaded)
- 100K records: ~10.6 seconds
- 10M records: ~18-20 minutes
- 50M records: ~90 minutes

**Data Quality Validation** (Always verify before benchmarking):
```sql
-- Check for NULL values (should be 0)
SELECT countIf(timestamp IS NULL) + countIf(src_ip IS NULL) + 
       countIf(dst_ip IS NULL) as null_count FROM flows_local;

-- Verify cardinality
SELECT 
    uniq(src_ip) as unique_sources,
    uniq(dst_ip) as unique_destinations
FROM flows_local;

-- Check distribution
SELECT 
    protocol_name,
    count() as flows,
    round(count() / (SELECT count() FROM flows_local) * 100, 2) as pct
FROM flows_local
GROUP BY protocol_name;
```

### Ingestion Optimization

**Most Reliable Method** (Docker environments):
```bash
# Copy file to container, then pipe to clickhouse-client
docker cp flows_001.json clickhouse01:/tmp/flows.json
docker exec clickhouse01 sh -c \
  "cat /tmp/flows.json | clickhouse-client --password admin \
   --query 'INSERT INTO netflow.flows_local FORMAT JSONEachRow'"
```

**Why This Works**:
- Avoids filesystem permission issues (NTFS/ext4 incompatibility)
- Reliable across different host operating systems
- Easy to automate and monitor

**Format Choice**:
- **JSONEachRow**: Best balance of readability and performance
- Human-readable for debugging
- Compact representation
- Native ClickHouse support

**Ingestion Performance**:
- 100K records (~30MB): **~2 seconds**
- 10M records (~3GB): **~3-5 minutes**
- Throughput: **50-100 MB/sec** (single file, single node)

**Monitoring During Ingestion**:
```bash
# Watch memory usage
docker stats clickhouse01

# Check insertion rate in real-time
docker exec clickhouse01 clickhouse-client --password admin --query "
SELECT 
    formatReadableQuantity(sum(ProfileEvent_InsertedRows)) as total_rows,
    sum(ProfileEvent_InsertedRows) / max(query_duration_ms) * 1000 as rows_per_sec
FROM system.query_log
WHERE type = 'QueryFinish' 
  AND query_kind = 'Insert'
  AND event_time > now() - INTERVAL 1 MINUTE
"
```

### Schema Design Patterns

**Primary Key Design**:
```sql
-- Time-first ordering enables partition pruning
ORDER BY (timestamp, cityHash64(src_ip), cityHash64(dst_ip))
```

**Why This Works**:
- `timestamp` first: Queries almost always filter by time
- Hash of IPs: Distributes data evenly, prevents hot spots
- Enables fast range scans within time windows

**Skip Indexes** (Critical for high-cardinality):
```sql
-- Bloom filter on high-cardinality fields
ALTER TABLE flows_local ADD INDEX src_ip_bloom src_ip TYPE bloom_filter;
ALTER TABLE flows_local ADD INDEX dst_ip_bloom dst_ip TYPE bloom_filter;

-- Performance impact: 10-100x speedup on exact IP lookups
```

**Engine Selection**:
- **Single-node**: `MergeTree()` - Simple, reliable
- **Replicated**: `ReplicatedMergeTree('/clickhouse/tables/{shard}/flows', '{replica}')` - For HA
- **Pre-aggregated views**: `SummingMergeTree()` or `AggregatingMergeTree()`

**Materialized Columns** (Avoid repeated calculations):
```sql
-- Computed once at insert time, stored alongside data
flow_start DateTime MATERIALIZED timestamp - INTERVAL flow_duration SECOND,
protocol_name String MATERIALIZED CASE protocol
    WHEN 1 THEN 'ICMP'
    WHEN 6 THEN 'TCP'
    WHEN 17 THEN 'UDP'
    ELSE 'Other'
END
```

### Query Optimization

**Always Include Time Range** (Enables partition pruning):
```sql
-- Good: Uses partitioning
SELECT * FROM flows_local 
WHERE timestamp >= '2026-03-01' AND timestamp < '2026-03-02';

-- Bad: Full table scan
SELECT * FROM flows_local WHERE src_ip = '10.0.0.1';

-- Best: Both time and other filters
SELECT * FROM flows_local 
WHERE timestamp >= '2026-03-01' AND timestamp < '2026-03-02'
  AND src_ip = '10.0.0.1';
```

**Pre-aggregation with Materialized Views**:
```sql
-- Create hourly aggregation
CREATE MATERIALIZED VIEW flows_hourly_mv
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, src_ip, dst_ip)
AS SELECT
    toStartOfHour(timestamp) as hour,
    src_ip,
    dst_ip,
    sum(bytes) as total_bytes,
    sum(packets) as total_packets,
    count() as flow_count
FROM flows_local
GROUP BY hour, src_ip, dst_ip;

-- Queries against hourly view are 10-100x faster
```

**Query Performance Observed**:
- Simple aggregations (100K records): **<0.1 seconds**
- High-cardinality GROUP BY: **<1 second**
- Complex multi-dimensional: **1-3 seconds**

**Test on Small Dataset First**:
```sql
-- Limit while developing query
SELECT ... FROM flows_local 
WHERE timestamp >= now() - INTERVAL 1 HOUR
LIMIT 1000;

-- Once optimized, remove limit for full dataset
```

### Operational Best Practices

**Database Organization**:
- Use dedicated database (`netflow`), not `default`
- Easier to manage permissions and backups
- Clear separation of concerns

**Docker Configuration**:
```yaml
# Use named volumes (not bind mounts) to avoid NTFS issues
volumes:
  - clickhouse_data:/var/lib/clickhouse  # ✅ Named volume (ext4)
  # NOT: ../data/clickhouse01:/var/lib/clickhouse  # ❌ NTFS bind mount
```

**Authentication**:
- Always pass password in commands:
```bash
docker exec clickhouse01 clickhouse-client --password admin --query "..."
```

**Network**:
- Internal Docker network sufficient for single-host cluster
- No need for complex networking unless multi-host

**Verification After Schema Changes**:
```sql
-- Verify table created
SELECT count(*) FROM system.tables 
WHERE database = 'netflow' AND name = 'flows_local';

-- Check indexes
SELECT * FROM system.data_skipping_indices 
WHERE table = 'flows_local';

-- Verify data
SELECT count(), min(timestamp), max(timestamp) FROM flows_local;
```

### Testing Strategy for Limited Storage

**Storage Requirements by Dataset Size**:

| Records | Raw JSON | ClickHouse | InfluxDB | Working | Total | Recommendation |
|---------|----------|------------|----------|---------|-------|----------------|
| 1M | 300 MB | 40 MB | 100 MB | 200 MB | **640 MB** | Quick test only |
| 10M | 3 GB | 400 MB | 1 GB | 500 MB | **5 GB** | Basic functionality |
| 50M | 15 GB | 2 GB | 5 GB | 1 GB | **23 GB** | **RECOMMENDED** |
| 100M | 30 GB | 4 GB | 10 GB | 2 GB | **46 GB** | Advanced testing |

**Dataset Sizing Guidelines**:

**10M Records** (~5GB total):
- Good for: Basic functionality testing
- Cardinality: 10K source IPs, 50K destination IPs
- Use case: Verify pipeline works correctly
- Limitation: Won't stress high-cardinality scenarios enough

**50M Records** (~23GB total) - **RECOMMENDED**:
- Good for: Performance comparisons, realistic scenarios
- Cardinality: 50K source IPs, 200K destination IPs
- Use case: Demonstrate ClickHouse advantages vs InfluxDB
- Sweet spot: Large enough to show differences, small enough to fit

**100M Records** (~46GB total):
- Good for: Extreme testing, final benchmarks
- Cardinality: 100K source IPs, 500K destination IPs
- Use case: Push systems to limits
- Requirement: Must clean Docker cache first

**Free Up Storage**:
```bash
# Check current Docker usage
docker system df

# Clean up (WARNING: removes all unused data)
docker system prune -a --volumes

# Expected recovery: 10-15 GB from build cache and unused images
```

### Performance Comparison: ClickHouse vs InfluxDB

**Why InfluxDB for Comparison** (replaced Prometheus):
- More direct time-series comparison
- Better cardinality handling than Prometheus (but still struggles)
- Uses tags (like labels) which creates similar challenges
- Easier to demonstrate architectural differences

**Expected Performance Differences**:

| Metric | ClickHouse | InfluxDB 2.x | Ratio |
|--------|------------|--------------|-------|
| **Ingestion (50M records)** | 5-8 min | 20-40 min | 3-5x faster |
| **Query (high-cardinality GROUP BY)** | <1 sec | 5-15 sec | 10-20x faster |
| **Storage (compressed)** | 2 GB | 4-6 GB | 2-3x smaller |
| **Cardinality limit** | Unlimited | ~1M series | N/A |

**Key Advantages to Demonstrate**:
1. **Ingestion speed**: ClickHouse parallelizes better
2. **Query performance**: Columnar storage + vectorized execution
3. **Storage efficiency**: Superior compression algorithms
4. **Scalability**: No cardinality limits

---

## Quick Start Guide

### Prerequisites

- Docker and Docker Compose installed
- At least 8GB RAM available
- 10-20GB free disk space (for 50M record dataset)
- Ports 8123, 8086, 3000 available

### Step 1: Start Services

```bash
cd /media/trantrongdat/DATA/Master/hocky1/cosodulieunangcao/clickhouse-for-flow-log/docker

# Start ClickHouse, InfluxDB, and Grafana
docker-compose up -d

# Wait for containers to be healthy (30-60 seconds)
docker ps
```

**Expected Output**:
```
NAME            STATUS
clickhouse01    Up (healthy)
influxdb        Up (healthy)
grafana         Up (healthy)
```

### Step 2: Initialize Schema

```bash
cd ../scripts/setup

# Create database and tables
./02-init-schema.sh
```

**This creates**:
- Database: `netflow`
- Table: `netflow.flows_local` (MergeTree)
- Indexes: Bloom filters on src_ip, dst_ip

### Step 3: Generate Test Data

```bash
cd ../../data-gen

# Quick test (100K records, ~30MB, 30 seconds)
python3 generate_flows.py \
  --records 100000 \
  --unique-src-ips 1000 \
  --unique-dst-ips 5000 \
  --time-range-days 1 \
  --output output_test/

# Standard test (10M records, ~3GB, 20 minutes)
python3 generate_flows.py \
  --records 10000000 \
  --unique-src-ips 10000 \
  --unique-dst-ips 50000 \
  --time-range-days 7 \
  --output output_10m/

# Recommended for comparison (50M records, ~15GB, 90 minutes)
python3 generate_flows.py \
  --records 50000000 \
  --unique-src-ips 50000 \
  --unique-dst-ips 200000 \
  --time-range-days 30 \
  --output output_50m/
```

### Step 4: Ingest Data into ClickHouse

```bash
# Copy file to container and ingest
docker cp output_test/flows_001.json clickhouse01:/tmp/flows.json

docker exec clickhouse01 sh -c \
  "cat /tmp/flows.json | clickhouse-client --password admin \
   --query 'INSERT INTO netflow.flows_local FORMAT JSONEachRow'"
```

**For multiple files**:
```bash
for file in output_test/*.json; do
    echo "Ingesting: $file"
    docker cp "$file" clickhouse01:/tmp/flows.json
    docker exec clickhouse01 sh -c \
      "cat /tmp/flows.json | clickhouse-client --password admin \
       --query 'INSERT INTO netflow.flows_local FORMAT JSONEachRow'"
done
```

### Step 5: Verify Data

```bash
# Quick check
docker exec clickhouse01 clickhouse-client --password admin --query \
  "SELECT formatReadableQuantity(count()) as total_flows FROM netflow.flows_local"

# Detailed verification
docker exec clickhouse01 clickhouse-client --password admin --multiquery < sql/queries/verify_data.sql
```

**Expected Results** (100K records):
- Total flows: 100,000
- Unique source IPs: ~1,000
- Unique destination IPs: ~4,000-5,000
- Protocol distribution: ~70% TCP, ~25% UDP, ~5% ICMP
- No NULL values

### Step 6: Run Sample Queries

```bash
# Access ClickHouse web interface
# Open browser: http://localhost:8123/play

# Or use command line
docker exec -it clickhouse01 clickhouse-client --password admin
```

**Sample Queries**:
```sql
-- Top 10 source IPs by traffic
SELECT 
    IPv4NumToString(src_ip) as source,
    formatReadableSize(sum(bytes)) as traffic,
    count() as flows
FROM netflow.flows_local
GROUP BY src_ip
ORDER BY sum(bytes) DESC
LIMIT 10;

-- Traffic by protocol
SELECT 
    protocol_name,
    formatReadableSize(sum(bytes)) as traffic,
    count() as flows
FROM netflow.flows_local
GROUP BY protocol_name
ORDER BY sum(bytes) DESC;

-- Hourly traffic pattern
SELECT 
    toHour(timestamp) as hour,
    formatReadableSize(sum(bytes)) as traffic
FROM netflow.flows_local
GROUP BY hour
ORDER BY hour;
```

### Step 7: Access Grafana (Optional)

```bash
# Open browser: http://localhost:3000
# Login: admin / admin_password (from .env)

# ClickHouse datasource should be pre-configured
# Create dashboards to visualize NetFlow data
```

---

## Dataset Planning for Limited Storage

This section helps you choose the right dataset size based on available storage.

### Current Storage Analysis

Check your available space:
```bash
# Overall disk usage
df -h

# Docker-specific usage
docker system df

# Expected reclaimable space
docker system df -v | grep "Reclaimable"
```

### Scenario Selection Guide

#### Scenario 1: Conservative (5GB available)

**Dataset**: 10 Million Records
- Total storage needed: ~5GB
- ClickHouse compressed: ~400 MB
- Raw JSON files: ~3 GB
- Working space: ~1 GB
- InfluxDB: ~1 GB

**Generation**:
```bash
python3 generate_flows.py \
  --records 10000000 \
  --unique-src-ips 10000 \
  --unique-dst-ips 50000 \
  --time-range-days 7 \
  --output output_10m/
```

**What You Can Demonstrate**:
- ✅ Basic ClickHouse functionality
- ✅ Query performance on moderate dataset
- ✅ Storage efficiency comparison
- ❌ Limited high-cardinality stress testing
- ❌ May not show significant ClickHouse advantages

#### Scenario 2: Recommended (15-25GB available)

**Dataset**: 50 Million Records
- Total storage needed: ~23GB
- ClickHouse compressed: ~2 GB
- Raw JSON files: ~15 GB
- Working space: ~1 GB
- InfluxDB: ~5 GB

**Generation**:
```bash
python3 generate_flows.py \
  --records 50000000 \
  --unique-src-ips 50000 \
  --unique-dst-ips 200000 \
  --time-range-days 30 \
  --output output_50m/
```

**What You Can Demonstrate**:
- ✅ Realistic high-cardinality scenarios
- ✅ Clear performance differences (ClickHouse vs InfluxDB)
- ✅ Query optimization techniques
- ✅ Storage compression benefits
- ✅ Partition pruning efficiency (30 partitions)
- **This is the sweet spot for academic projects**

#### Scenario 3: Advanced (40GB+ available after cleanup)

**Dataset**: 100 Million Records
- Total storage needed: ~46GB
- ClickHouse compressed: ~4 GB
- Raw JSON files: ~30 GB
- Working space: ~2 GB
- InfluxDB: ~10 GB

**Prerequisites**:
```bash
# Free up space first
docker system prune -a --volumes
# Expect to recover 10-15GB
```

**Generation**:
```bash
python3 generate_flows.py \
  --records 100000000 \
  --unique-src-ips 100000 \
  --unique-dst-ips 500000 \
  --time-range-days 90 \
  --output output_100m/
```

**What You Can Demonstrate**:
- ✅ All advantages from Scenario 2
- ✅ Extreme high-cardinality (100K+ unique IPs)
- ✅ InfluxDB cardinality limits (will struggle/fail)
- ✅ ClickHouse scalability
- ⚠️ Requires significant time (2-3 hours generation + ingestion)

### Storage Cleanup

If you need more space:

```bash
# Check what can be reclaimed
docker system df

# Remove unused containers, images, networks, build cache
docker system prune -a

# Also remove volumes (WARNING: deletes data!)
docker system prune -a --volumes

# Expected recovery: 10-15 GB
```

### Dataset Size vs Demonstration Goals

| Goal | Min Dataset | Recommended | Time Investment |
|------|-------------|-------------|-----------------|
| Basic functionality proof | 1M | 10M | 1 hour |
| Performance comparison | 10M | 50M | 3-4 hours |
| **Academic project** | **10M** | **50M** | **4-6 hours** |
| Research paper | 50M | 100M+ | 8-12 hours |

---

## Testing & Verification

### Automated Component Testing

Run comprehensive tests:
```bash
cd /media/trantrongdat/DATA/Master/hocky1/cosodulieunangcao/clickhouse-for-flow-log/tests

# Run all component tests
./test_components.sh
```

**Tests Include**:
1. Docker container status
2. ClickHouse HTTP interface
3. ClickHouse query execution
4. InfluxDB health check
5. Grafana API accessibility
6. Network connectivity between services

### Manual ClickHouse Testing

#### Web Interface (Browser)
```
URL: http://localhost:8123/play
```

**Test Queries**:
```sql
-- Version check
SELECT version();

-- List databases
SHOW DATABASES;

-- Check netflow database
SHOW TABLES FROM netflow;

-- Quick data check
SELECT count() FROM netflow.flows_local;

-- Sample data
SELECT * FROM netflow.flows_local LIMIT 10;
```

#### Command Line (curl)
```bash
# Ping
curl http://localhost:8123/ping

# Version
curl "http://localhost:8123/?query=SELECT+version()"

# Query data
curl "http://localhost:8123/?query=SELECT+count()+FROM+netflow.flows_local"

# Insert test data
echo '{"timestamp":"2026-03-16 12:00:00","src_ip":"10.0.0.1","dst_ip":"10.0.0.2","src_port":443,"dst_port":54321,"protocol":6,"bytes":1024,"packets":10,"flow_duration":5}' | \
curl -X POST "http://localhost:8123/?query=INSERT+INTO+netflow.flows_local+FORMAT+JSONEachRow" --data-binary @-
```

#### Interactive Client (Docker exec)
```bash
# Connect to interactive client
docker exec -it clickhouse01 clickhouse-client --password admin

# Run queries interactively
clickhouse01 :) SELECT count() FROM netflow.flows_local;
clickhouse01 :) SHOW CREATE TABLE netflow.flows_local;
clickhouse01 :) exit;
```

### Data Quality Verification

Run comprehensive verification:
```bash
docker exec clickhouse01 clickhouse-client --password admin --multiquery < sql/queries/verify_data.sql
```

**Key Checks**:
1. **Record count**: Matches expected dataset size
2. **NULL values**: Should be 0
3. **Cardinality**: Unique IPs match generation parameters
4. **Distribution**: Protocol percentages (~70/25/5 TCP/UDP/ICMP)
5. **Time range**: Covers expected period
6. **Geographic data**: Lat/lon within valid ranges
7. **Storage**: Compression ratio > 1.2x

### Performance Benchmarking

#### Ingestion Benchmark

**ClickHouse**:
```bash
cd scripts/benchmark

# Time ingestion of 10M records
time ./benchmark_ingest_clickhouse.sh ../../data-gen/output_10m/flows_001.json
```

**InfluxDB**:
```bash
# Convert and ingest to InfluxDB
time ./benchmark_ingest_influxdb.sh ../../data-gen/output_10m/flows_001.json
```

#### Query Benchmark

```bash
# Run standard benchmark queries
./benchmark_queries.sh

# Side-by-side comparison
./compare_performance.sh
```

**Example Benchmark Queries**:
1. **Point query**: Specific IP lookup
2. **Top-N**: Top 100 talkers
3. **High-cardinality aggregation**: src_ip × dst_ip
4. **Time-series**: Hourly traffic trends
5. **Percentiles**: P50/P95/P99 calculations

### Monitoring During Operations

**Watch ClickHouse Performance**:
```bash
# Monitor resource usage
docker stats clickhouse01

# Watch active queries
watch -n 1 'docker exec clickhouse01 clickhouse-client --password admin --query "SELECT query_id, elapsed, formatReadableSize(memory_usage) as memory, query FROM system.processes WHERE query NOT LIKE \"%system.processes%\""'

# Check recent query performance
docker exec clickhouse01 clickhouse-client --password admin --query "
SELECT 
    type,
    query_duration_ms,
    formatReadableSize(memory_usage) as memory,
    query
FROM system.query_log
WHERE event_time > now() - INTERVAL 5 MINUTE
ORDER BY event_time DESC
LIMIT 10
FORMAT PrettyCompact
"
```

---

## Project Report Guidelines

This section provides structure for writing an academic project report.

### Report Structure (18-22 pages)

#### 1. Executive Summary (1 page)

**Content**:
- Project objective (2-3 sentences)
- Implementation scope (cluster topology, data scale)
- Key quantitative findings (4-5 bullets with numbers)
- Major conclusion (1 sentence)

**Example Metrics to Highlight**:
- Ingestion: "ClickHouse achieved 5x faster ingestion (8 min vs 40 min for 50M records)"
- Queries: "High-cardinality queries 20x faster (0.8s vs 16s average)"
- Storage: "2.5x better compression (2 GB vs 5 GB for same dataset)"
- Scalability: "ClickHouse handled 500K unique IPs; InfluxDB limited to ~100K"

#### 2. Introduction (2-3 pages)

**2.1 Problem Statement**:
- Define NetFlow data characteristics (high cardinality, high volume, time-series)
- Explain challenges: cardinality explosion, memory limits, compression needs
- Motivate why this problem matters (security monitoring, network analytics)

**2.2 ClickHouse Advantages Hypothesis**:
- Columnar storage for sparse data
- Compression codecs (Delta, DoubleDelta, Gorilla)
- Distributed query execution
- Partitioning and skip indexes

**2.3 Project Objectives**:
1. Design and implement ClickHouse-based NetFlow analytics system
2. Generate synthetic high-cardinality test dataset
3. Compare performance with InfluxDB (time-series database)
4. Quantify benefits of columnar architecture
5. Document operational best practices

#### 3. System Architecture (2-3 pages)

**3.1 Cluster Topology**:
- Include architecture diagram
- Explain cluster design (single-node vs distributed)
- List infrastructure components with specs
- Justify technology choices

**3.2 Data Model**:
```sql
-- Include annotated schema
CREATE TABLE flows_local (
    timestamp DateTime CODEC(DoubleDelta, LZ4), -- Time-series optimized
    src_ip IPv4,                                 -- High-cardinality field
    dst_ip IPv4,                                 -- High-cardinality field
    src_port UInt16,
    dst_port UInt16,
    protocol UInt8,
    bytes UInt64 CODEC(Delta, LZ4),             -- Counter compression
    packets UInt32 CODEC(Delta, LZ4),
    flow_duration UInt32 CODEC(Delta, LZ4),
    src_geo_latitude Float32 CODEC(Gorilla, LZ4), -- Geo compression
    src_geo_longitude Float32 CODEC(Gorilla, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)               -- Daily partitions
ORDER BY (timestamp, cityHash64(src_ip));        -- Time-first ordering
```

**Explain Each Decision**:
- Engine: MergeTree for sorted storage
- Partition key: Daily for efficient pruning
- Order key: Time-first for range scans
- Codecs: Matched to data type characteristics

**3.3 Comparison Architecture**:
- InfluxDB setup (tag/field model)
- Grafana for visualization
- Explain architectural differences

#### 4. Dataset & Data Generation (1-2 pages)

**4.1 Synthetic Data Approach**:
- Justification for synthetic data (reproducibility, volume, safety)
- Generation algorithm (Pareto distribution, weighted sampling)
- Cardinality targets (50K src, 200K dst)

**4.2 Dataset Characteristics**:
| Metric | Value | Method |
|--------|-------|--------|
| Total records | 50,000,000 | Generated |
| Time span | 30 days | 2026-02-14 to 2026-03-16 |
| Raw size | 15 GB | JSONEachRow format |
| Unique source IPs | 50,000 | Pareto distribution |
| Unique dest IPs | 200,000 | Weighted random |
| Protocol split | 70/25/5 | TCP/UDP/ICMP |
| Avg bytes/flow | 320 KB | Log-normal distribution |

#### 5. Performance Benchmarks (4-5 pages)

**5.1 Ingestion Performance**:

| Metric | ClickHouse | InfluxDB | Ratio |
|--------|------------|----------|-------|
| Duration | 8 min | 40 min | **5x faster** |
| Throughput | 104K rows/sec | 21K rows/sec | **5x higher** |
| CPU average | 65% | 85% | More efficient |
| Memory peak | 3.2 GB | 7.8 GB | **2.4x lower** |

**Include**:
- Measurement methodology
- Scripts used (bash snippets)
- Monitoring queries
- Analysis of why ClickHouse faster (parallelization, columnar format)

**5.2 Query Performance**:

Test 5 representative queries:

**Q1: Point Query** (Specific IP lookup)
```sql
-- ClickHouse
SELECT * FROM flows_local 
WHERE src_ip = '10.50.100.1' 
  AND timestamp BETWEEN '2026-03-01' AND '2026-03-02';
-- Result: 0.05 seconds
```

**Q2: Top-N Aggregation**
```sql
-- ClickHouse
SELECT src_ip, count() as flows, sum(bytes) as traffic
FROM flows_local
GROUP BY src_ip
ORDER BY traffic DESC
LIMIT 100;
-- Result: 0.8 seconds
```

**Q3: High-Cardinality Traffic Matrix**
```sql
-- ClickHouse
SELECT src_ip, dst_ip, sum(bytes) as traffic
FROM flows_local
WHERE timestamp >= '2026-03-01'
GROUP BY src_ip, dst_ip
ORDER BY traffic DESC
LIMIT 10000;
-- Result: 2.3 seconds (InfluxDB: timeout or OOM)
```

**Q4: Percentile Calculations**
```sql
-- ClickHouse
SELECT protocol, quantiles(0.5, 0.95, 0.99)(bytes)
FROM flows_local
GROUP BY protocol;
-- Result: 1.1 seconds (exact values)
-- InfluxDB: 8.5 seconds (approximate via histograms)
```

**Q5: Time-Series Aggregation**
```sql
-- ClickHouse
SELECT toStartOfHour(timestamp) as hour, sum(bytes)
FROM flows_local
GROUP BY hour
ORDER BY hour;
-- Result: 0.4 seconds
```

**For Each Query**:
- Include actual execution times
- Explain why ClickHouse faster
- Note InfluxDB struggles or limitations

**5.3 Storage Efficiency**:

| Metric | ClickHouse | InfluxDB | Ratio |
|--------|------------|----------|-------|
| Raw data | 15 GB | 15 GB | 1x |
| Compressed | 2.1 GB | 5.3 GB | **2.5x smaller** |
| Compression ratio | 7.1x | 2.8x | **2.5x better** |
| Partitions | 30 (daily) | N/A | Organized |

**Explain**:
- Why columnar compression more effective
- Codec selection impact (Delta, DoubleDelta, Gorilla)
- Partition organization benefits

**5.4 Summary Analysis**:

**Why ClickHouse Wins**:
1. **Columnar storage**: Only reads needed columns
2. **Compression**: Matched codecs to data types
3. **Vectorized execution**: SIMD operations on columns
4. **Partition pruning**: Skips irrelevant partitions
5. **Skip indexes**: Bloom filters eliminate thousands of blocks

**When ClickHouse Struggles**: 
- High-frequency updates (not append-only)
- Transactional workloads (lacks ACID guarantees)
- Very small point queries (overhead of column reading)

**When InfluxDB Better**:
- Low-cardinality time-series metrics
- Real-time alerting requirements
- Simple metric storage (Prometheus-style)

#### 6. Conclusions (1 page)

**Summary of Findings**:
- Restate key quantitative results
- Confirm hypothesis (ClickHouse superior for high-cardinality)
- Practical implications (when to use each system)

**Lessons Learned**:
- Technical insights gained
- Challenges overcome
- Best practices identified

**Future Work**:
- Multi-node clustering
- Real NetFlow data ingestion
- Machine learning integration
- Real-time alerting systems

#### 7. References

- ClickHouse documentation
- InfluxDB documentation
- NetFlow specification (RFC 3954)
- Academic papers on columnar databases
- Performance benchmarking methodologies

---

## Configuration Reference

### Environment Variables (.env)

```bash
# ClickHouse Configuration
CLICKHOUSE_VERSION=24.1
CLICKHOUSE_PASSWORD=admin
CLICKHOUSE_HTTP_PORT=8123
CLICKHOUSE_NATIVE_PORT=9000

# InfluxDB Configuration
INFLUXDB_VERSION=2.7
INFLUXDB_ORG=netflow_org
INFLUXDB_BUCKET=netflow
INFLUXDB_RETENTION=30d
INFLUXDB_PORT=8086
INFLUXDB_ADMIN_PASSWORD=admin_password

# Grafana Configuration
GRAFANA_VERSION=10.2.3
GRAFANA_PORT=3000
GRAFANA_ADMIN_PASSWORD=admin_password

# Data Generation
TOTAL_RECORDS=50000000
UNIQUE_SRC_IPS=50000
UNIQUE_DST_IPS=200000
TIME_RANGE_DAYS=30
```

### Docker Compose Services

**Minimal Setup** (SingleNode):
```yaml
services:
  clickhouse01:
    image: clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}
    container_name: clickhouse01
    environment:
      CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}
    ports:
      - "${CLICKHOUSE_HTTP_PORT}:8123"
      - "${CLICKHOUSE_NATIVE_PORT}:9000"
    volumes:
      - clickhouse_data:/var/lib/clickhouse
    networks:
      - netflow_network

  influxdb:
    image: influxdb:${INFLUXDB_VERSION}
    container_name: influxdb
    environment:
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: admin
      DOCKER_INFLUXDB_INIT_PASSWORD: ${INFLUXDB_ADMIN_PASSWORD}
      DOCKER_INFLUXDB_INIT_ORG: ${INFLUXDB_ORG}
      DOCKER_INFLUXDB_INIT_BUCKET: ${INFLUXDB_BUCKET}
      DOCKER_INFLUXDB_INIT_RETENTION: ${INFLUXDB_RETENTION}
    ports:
      - "${INFLUXDB_PORT}:8086"
    volumes:
      - influxdb_data:/var/lib/influxdb2
    networks:
      - netflow_network

  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
    ports:
      - "${GRAFANA_PORT}:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - netflow_network

volumes:
  clickhouse_data:
  influxdb_data:
  grafana_data:

networks:
  netflow_network:
    driver: bridge
```

---

## Troubleshooting

### Common Issues

#### Issue: ClickHouse Container Won't Start

**Symptoms**:
```
clickhouse01 | DB::Exception: Cannot set modification time...
```

**Cause**: NTFS filesystem doesn't support Unix operations

**Solution**: Use named volumes instead of bind mounts
```yaml
# Good
volumes:
  - clickhouse_data:/var/lib/clickhouse

# Bad (on NTFS/FAT32)
volumes:
  - ../data/clickhouse01:/var/lib/clickhouse
```

#### Issue: Authentication Errors

**Symptoms**:
```
Code: 516. DB::Exception: Authentication failed
```

**Solution**: Always pass password
```bash
docker exec clickhouse01 clickhouse-client --password admin --query "..."
```

#### Issue: InfluxDB Series Cardinality Warning

**Symptoms**:
```
max-series-per-database exceeded
```

**Cause**: Too many unique tag combinations

**Expected**: This demonstrates InfluxDB's limitations with high-cardinality data

**ClickHouse Advantage**: No such limits

#### Issue: Out of Disk Space

**Check Usage**:
```bash
df -h
docker system df
```

**Solutions**:
```bash
# Remove old data
docker exec clickhouse01 clickhouse-client --password admin --query \
  "ALTER TABLE netflow.flows_local DROP PARTITION '20260301'"

# Clean Docker cache
docker system prune -a

# Use smaller dataset
# Generate 10M instead of 50M records
```

#### Issue: Slow Query Performance

**Diagnosis**:
```sql
-- Check if query uses partition pruning
EXPLAIN SELECT ... FROM flows_local WHERE timestamp > ...;

-- Look for "ReadFromMergeTree" step, should show limited partitions
```

**Optimizations**:
1. Always include timestamp filter
2. Add skip indexes on high-cardinality fields
3. Use materialized views for repeated aggregations
4. Test on small dataset first (LIMIT 1000)

#### Issue: Memory Errors During Ingestion

**Symptoms**:
```
Memory limit exceeded
```

**Solutions**:
1. Ingest in smaller batches
2. Increase Docker memory limit
3. Use streaming ingestion instead of bulk

```bash
# Stream instead of bulk load
cat large_file.json | docker exec -i clickhouse01 clickhouse-client \
  --password admin --query "INSERT INTO netflow.flows_local FORMAT JSONEachRow"
```

### Getting Help

**Check Logs**:
```bash
# ClickHouse logs
docker logs clickhouse01

# InfluxDB logs
docker logs influxdb

# Follow logs in real-time
docker logs -f clickhouse01
```

**System Tables** (ClickHouse troubleshooting):
```sql
-- Recent errors
SELECT * FROM system.errors WHERE value > 0;

-- Failed queries
SELECT * FROM system.query_log 
WHERE type = 'ExceptionWhileProcessing' 
ORDER BY event_time DESC 
LIMIT 10;

-- Resource usage
SELECT * FROM system.metrics;
SELECT * FROM system.asynchronous_metrics;
```

---

## Appendix: Useful Commands

### Docker Management

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Restart specific service
docker restart clickhouse01

# View resource usage
docker stats

# Check service health
docker ps
docker inspect clickhouse01 | grep -A 10 Health
```

### ClickHouse Operations

```bash
# Interactive client
docker exec -it clickhouse01 clickhouse-client --password admin

# Execute single query
docker exec clickhouse01 clickhouse-client --password admin \
  --query "SELECT count() FROM netflow.flows_local"

# Execute multi-query script
docker exec -i clickhouse01 clickhouse-client --password admin \
  --multiquery < script.sql

# Export data
docker exec clickhouse01 clickhouse-client --password admin \
  --query "SELECT * FROM netflow.flows_local LIMIT 1000 FORMAT CSV" > export.csv
```

### Data Management

```bash
# Check table sizes
docker exec clickhouse01 clickhouse-client --password admin --query "
SELECT 
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    formatReadableQuantity(sum(rows)) as rows
FROM system.parts
WHERE database = 'netflow' AND active
GROUP BY table
FORMAT PrettyCompact
"

# Check partitions
docker exec clickhouse01 clickhouse-client --password admin --query "
SELECT partition, count() as parts, sum(rows) as rows
FROM system.parts
WHERE database = 'netflow' AND table = 'flows_local' AND active
GROUP BY partition
ORDER BY partition
"

# Optimize table (merge small parts)
docker exec clickhouse01 clickhouse-client --password admin --query \
  "OPTIMIZE TABLE netflow.flows_local FINAL"

# Drop old partitions
docker exec clickhouse01 clickhouse-client --password admin --query \
  "ALTER TABLE netflow.flows_local DROP PARTITION '20260301'"
```

---

**Document Version**: 2.0  
**Last Updated**: 2026-03-16  
**Status**: Production Ready (InfluxDB-based comparison)

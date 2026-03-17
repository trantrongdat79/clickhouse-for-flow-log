# AI Agent Guidelines for ClickHouse NetFlow Project

## Purpose
This document provides guidelines for AI agents working on the ClickHouse high-cardinality NetFlow analytics project. These principles ensure consistency, maintainability, and clarity across all project components.

---

## Core Principles

### 1. Simplicity First
- **Keep configurations simple and modular**
  - Prefer single-responsibility files over monolithic configs
  - Use clear, self-documenting naming conventions
  - Avoid premature optimization
  
- **Avoid unnecessary complexity**
  - Don't add features "just in case"
  - Choose straightforward solutions over clever ones
  - Avoid over-validation and excessive error handling
  - Document prerequisites and manual checks instead of coding them
  - Trust users to verify environment before running scripts 

### 2. Modularity
- **Configuration files**: One concern per file
  - Example: `remote_servers.xml` only defines cluster topology
  - Separate security configs from performance configs
  
- **Scripts**: Single-purpose, composable
  - Each script should do one thing well
  - Chain scripts together rather than creating monoliths
  - Use clear exit codes (0=success, non-zero=failure)

### 3. Documentation Standards
- **Every file needs context**
  - SQL files: Purpose, dependencies, expected outcome
  - Scripts: Usage, parameters, examples
  - Configs: What it controls, default values, when to modify
  
- **Self-documenting code**
  - Use descriptive variable names (`CLICKHOUSE_MASTER_HOST` not `CH1`)
  - Comment the "why", not the "what"
  - Include examples in headers

---

## File Organization Rules

### Configuration Files
```bash
# Good: Modular, clear purpose
clickhouse-config/
├── config.d/
│   ├── remote_servers.xml    # Cluster topology only
│   ├── macros.xml            # Node-specific variables
│   └── storage.xml           # Storage policies only

# Bad: Everything in one file
clickhouse-config/
└── config.xml                # 500 lines of mixed concerns
```

### Scripts
```bash
# Good: Single-purpose scripts
scripts/
├── setup/
│   ├── 01-start-cluster.sh      # Just start containers
│   ├── 02-wait-for-health.sh    # Just wait for readiness
│   └── 03-init-schema.sh        # Just create tables

# Bad: Do-everything script
scripts/
└── setup-everything.sh          # 300 lines doing all tasks
```

---

## Coding Standards

### Shell Scripts
```bash
#!/bin/bash
# Script: example.sh
# Purpose: Brief description of what it does
# Usage: ./example.sh [--option value]
# Author: [Your Name]
# Date: 2026-03-06

set -euo pipefail  # Fail fast, catch errors early

# Configuration (environment variables with defaults)
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
TIMEOUT="${TIMEOUT:-30}"

# Functions should have clear names and single purpose
function wait_for_clickhouse() {
    local max_attempts=$1
    # Implementation...
}

# Main execution
main() {
    echo "Starting process..."
    # Do the work
}

main "$@"
```

### SQL Files
```sql
-- filepath: sql/schema/01-flows-local.sql
-- Purpose: Create replicated table for flow data on each ClickHouse node
-- Dependencies: Cluster must be configured, ZooKeeper running
-- Expected result: One table per node with shared schema
-- Usage: Execute on any cluster node with ON CLUSTER clause

-- Drop existing table if in development mode
-- DROP TABLE IF EXISTS flows_local ON CLUSTER '{cluster}';

CREATE TABLE IF NOT EXISTS flows_local ON CLUSTER '{cluster}'
(
    timestamp DateTime COMMENT 'Flow start time',
    src_ip IPv4 COMMENT 'Source IP address',
    -- More fields...
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/flows', '{replica}')
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, cityHash64(src_ip))
COMMENT 'Raw NetFlow data - replicated across cluster';
```

### Python Scripts
```python
#!/usr/bin/env python3
"""
Module: generate_flows.py
Purpose: Generate synthetic NetFlow data for testing
Usage: python generate_flows.py --records 1000000 --output data/

Dependencies:
    - Python 3.8+
    - No external libraries (uses stdlib only)
"""

import argparse
import json
from datetime import datetime, timedelta
from typing import Iterator, Dict

# Configuration constants at module level
DEFAULT_RECORDS = 1_000_000
PROTOCOLS = {'TCP': 6, 'UDP': 17, 'ICMP': 1}

def generate_flow(timestamp: datetime) -> Dict:
    """Generate a single flow record.
    
    Args:
        timestamp: Flow start time
        
    Returns:
        Dictionary representing one flow record
    """
    # Implementation...
    pass

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    # Implementation...
    
if __name__ == '__main__':
    main()
```

---

## Development Workflow

### Before Making Changes
1. **Understand the scope**: Read relevant docs
2. **Check dependencies**: What relies on this?
3. **Plan backwards**: What's the end goal?
4. **Start simple**: Implement minimal working version first

### Making Changes
1. **One logical change per commit** (when using version control)
2. **Test incrementally**: Don't write 100 lines before testing
3. **Validate assumptions**: Check configs actually work
4. **Document as you go**: Update docs alongside code

### After Changes
1. **Test the happy path**: Does it work as expected?
2. **Test error cases**: What happens when it fails?
3. **Update documentation**: READMEs, comments, runbooks
4. **Clean up**: Remove debug code, temporary files

---

## Common Patterns

### Error Handling (Bash)
```bash
# Good: Simple and direct - document prerequisites instead
# Prerequisites (document in script header):
#   - DATA_FILE must exist
#   - ClickHouse must be running and accessible
#   - Network connectivity required

function ingest_data() {
    local data_file=$1
    curl -X POST "http://clickhouse:8123/" --data-binary @"$data_file"
    echo "Ingested $data_file"
}
```

### Configuration Management
```bash
# Good: Centralized config with defaults
# Load from .env file if exists, use defaults otherwise
set -a  # Auto-export variables
source "${CONFIG_FILE:-.env}" 2>/dev/null || true
set +a

CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-8123}"
```

### Idempotency
```sql
-- Good: Can be run multiple times safely
CREATE TABLE IF NOT EXISTS flows_local ...;
ALTER TABLE flows_local ADD INDEX IF NOT EXISTS src_ip_bloom ...;

-- Bad: Fails on second run
CREATE TABLE flows_local ...;
ALTER TABLE flows_local ADD INDEX src_ip_bloom ...;
```

---

## Testing Guidelines

### Script Testing
```bash
# Keep scripts simple - document requirements in header instead
# Required environment variables:
#   CLICKHOUSE_HOST - ClickHouse server hostname
#   DATA_DIR - Directory containing data files
# 
# Verify manually before running:
#   echo $CLICKHOUSE_HOST
#   ls -la $DATA_DIR

function process_data() {
    # Direct implementation without validation overhead
    clickhouse-client --host "$CLICKHOUSE_HOST" --query "..."
}
```

### SQL Testing
```sql
-- Include validation queries after schema changes
-- Verify table was created
SELECT count(*) FROM system.tables 
WHERE database = 'default' AND name = 'flows_local';
-- Expected: 1

-- Verify replication is working
SELECT * FROM system.replicas 
WHERE table = 'flows_local';
-- Expected: One row per replica
```

---

## Anti-Patterns to Avoid

### ❌ Don't Do This
```bash
# Silent failures
curl http://clickhouse:8123/ || true

# Unclear variable names
CH_01="clickhouse01"
FK_PT="8123"

# Hard-coded paths
cat /home/user/my-data/flows.json | ...

# Mixed concerns
# Script that: starts cluster, creates schema, ingests data, runs tests

# Over-engineered validation (adds complexity without real value)
function validate_everything() {
    check_docker_running
    check_container_exists
    check_network_connectivity
    check_port_availability
    check_disk_space
    # ... 50 more checks
}
```

### ✅ Do This Instead
```bash
# Script: ingest-data.sh
# Prerequisites (verify manually before running):
#   - ClickHouse is running on port 8123
#   - DATA_DIR is set and contains .json files
#   - User has permissions to read data files

# Clear variable names with defaults
CLICKHOUSE_MASTER_HOST="${CLICKHOUSE_MASTER_HOST:-clickhouse01}"
CLICKHOUSE_HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"

# Simple, direct implementation
docker exec "$CLICKHOUSE_MASTER_HOST" clickhouse-client --query "$SQL"

# Configurable paths
DATA_DIR="${DATA_DIR:-./data}"
cat "${DATA_DIR}/flows.json" | clickhouse-client --query "INSERT INTO flows FORMAT JSONEachRow"

# Single-purpose scripts
./scripts/setup/01-start-cluster.sh
./scripts/setup/02-init-schema.sh
./scripts/ingestion/ingest.sh
./scripts/testing/run-tests.sh
```

---

## Documentation Requirements

### README Files
Every major directory should have a README.md with:
- **Purpose**: What this directory contains
- **Usage**: How to use the files
- **Dependencies**: What must exist first
- **Examples**: Common use cases

### Script Headers
All scripts must include:
```bash
#!/bin/bash
# Script: script-name.sh
# Purpose: One-line description
# Usage: ./script-name.sh [OPTIONS]
#   -h, --help      Show this help
#   -v, --verbose   Enable verbose output
# Examples:
#   ./script-name.sh --verbose
# Dependencies: docker, docker-compose
# Author: [Name]
# Date: YYYY-MM-DD
```

### Configuration Comments
```xml
<!-- filepath: clickhouse-config/config.d/remote_servers.xml -->
<!-- 
Purpose: Define ClickHouse cluster topology
When to modify: When adding/removing nodes
Default: 2 shards with 2 replicas each
Related files: macros.xml (node-specific settings)
-->
<clickhouse>
    <!-- Cluster definition -->
</clickhouse>
```

---

## Troubleshooting Guide for Agents

### When Something Doesn't Work
1. **Check the basics first**
   - Is Docker running?
   - Are containers healthy? (`docker ps`)
   - Are ports available? (`netstat -tuln`)

2. **Look at logs**
   - `docker logs clickhouse01`
   - `docker logs zookeeper01`
   - Check ClickHouse system tables

3. **Verify connectivity**
   - Can containers ping each other?
   - Is ZooKeeper ensemble formed?
   - Can ClickHouse connect to ZooKeeper?

4. **Check permissions**
   - File permissions correct?
   - User has docker access?
   - Volumes mounted correctly?

### Common Issues and Solutions

**Issue: Cluster won't form**
- Check: ZooKeeper logs first
- Check: `remote_servers.xml` hostnames match container names
- Check: All nodes can resolve each other

**Issue: Replication not working**
- Check: ZooKeeper is accessible from all nodes
- Check: `macros.xml` has unique values per node
- Check: Replica paths in ZooKeeper are created

**Issue: Scripts fail silently**
- Add: `set -e` at start to exit on errors
- Check: Script prerequisites documented?
- Verify: Environment matches documented requirements manually

---

## ClickHouse-Specific Insights

This section captures practical lessons learned from implementing the NetFlow analytics project.

### Storage Configuration

**Always use dedicated database, not `default`**:
```sql
-- Good: Organized, easy to manage
CREATE DATABASE netflow;
USE netflow;
CREATE TABLE flows_local ...;

-- Bad: Pollutes default database
CREATE TABLE flows_local ...;
```

**Docker volumes > bind mounts** (avoids filesystem issues):
```yaml
# Good: Named volume (works on all filesystems)
volumes:
  - clickhouse_data:/var/lib/clickhouse

# Bad: Bind mount (fails on NTFS with permission errors)
volumes:
  - ../data/clickhouse01:/var/lib/clickhouse
```

**Monitor compression ratios** during testing (should be >1.2x):
```sql
SELECT 
    formatReadableSize(sum(bytes_on_disk)) as compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed,
    round(sum(data_uncompressed_bytes) / sum(bytes_on_disk), 2) as ratio
FROM system.parts
WHERE database = 'netflow' AND active;
-- Expected: ratio > 1.2 (NetFlow typically 1.3-1.5x)
```

### Schema Design Patterns

**Primary Key: Time-first ordering** enables partition pruning:
```sql
-- Good: Time first, then high-cardinality fields
ORDER BY (timestamp, cityHash64(src_ip), cityHash64(dst_ip))

-- Why: Most queries filter by time range
-- Enables: Partition pruning (dramatic performance improvement)
```

**Codec selection** matched to data characteristics:
```sql
-- Timestamps: DoubleDelta (time-series data)
timestamp DateTime CODEC(DoubleDelta, LZ4)

-- Counters: Delta (incremental values)
bytes UInt64 CODEC(Delta, LZ4)
packets UInt32 CODEC(Delta, LZ4)

-- Floats: Gorilla (floating point compression)
geo_latitude Float32 CODEC(Gorilla, LZ4)
```

**Skip Indexes: Bloom filters** on high-cardinality dimensions:
```sql
-- Critical for IP lookups (10-100x speedup)
ALTER TABLE flows_local ADD INDEX src_ip_bloom src_ip TYPE bloom_filter;
ALTER TABLE flows_local ADD INDEX dst_ip_bloom dst_ip TYPE bloom_filter;

-- Test impact:
-- Without index: 5-10 seconds for specific IP lookup
-- With index: <0.1 seconds
```

** Partitioning: Daily partitions** work well for 30-90 day retention:
```sql
-- Good: Daily partitioning
PARTITION BY toYYYYMMDD(timestamp)
-- Creates: 30 partitions for 30 days (manageable)
-- Enables: Efficient partition pruning in queries

-- Avoid: Too granular (hourly = 720 partitions for 30 days)
-- Avoid: Too coarse (monthly = queries scan 30+ days when filtering by day)
```

### Ingestion Best Practices

**JSONEachRow format** balances readability and performance:
```bash
# Good: Human-readable, efficient, native support
echo '{"timestamp":"2026-03-16 12:00:00","src_ip":"10.0.0.1",...}' | \
  clickhouse-client --query "INSERT INTO flows FORMAT JSONEachRow"

# Alternative: CSV (faster but less flexible)
# Alternative: Native (fastest but binary, hard to debug)
```

**Docker copy + pipe method** most reliable across platforms:
```bash
# Most reliable (avoids filesystem permission issues)
docker cp flows.json clickhouse01:/tmp/flows.json
docker exec clickhouse01 sh -c \
  "cat /tmp/flows.json | clickhouse-client --password admin \
   --query 'INSERT INTO netflow.flows_local FORMAT JSONEachRow'"

# Avoid: Direct file path (fails with NTFS permissions)
docker exec clickhouse01 clickhouse-client \
  --query "INSERT INTO flows FORMAT JSONEachRow" < /mnt/data/flows.json
```

**Monitor memory** during ingestion:
```bash
# Real-time monitoring
watch -n 1 'docker stats clickhouse01 --no-stream'

# Check insertion rate
docker exec clickhouse01 clickhouse-client --password admin --query "
SELECT 
    sum(ProfileEvent_InsertedRows) as total_rows,
    sum(ProfileEvent_InsertedRows) / max(query_duration_ms) * 1000 as rows_per_sec
FROM system.query_log
WHERE type = 'QueryFinish' AND query_kind = 'Insert'
  AND event_time > now() - INTERVAL 1 MINUTE
"
```

### Query Optimization

**Always include timestamp range** (enables partition pruning):
```sql
-- Good: Uses partition pruning
SELECT * FROM flows 
WHERE timestamp >= '2026-03-01' AND timestamp < '2026-03-02'
  AND src_ip = '10.0.0.1';

-- Bad: Full table scan (slow!)
SELECT * FROM flows WHERE src_ip = '10.0.0.1';

-- Verify with EXPLAIN:
EXPLAIN SELECT ... -- Check for "ReadFromMergeTree" with partition pruning
```

**Materialized views** for repeated aggregations:
```sql
-- Pre-aggregate hourly statistics (10-100x speedup)
CREATE MATERIALIZED VIEW flows_hourly_mv
ENGINE = SummingMergeTree()
ORDER BY (hour, src_ip, dst_ip)
AS SELECT
    toStartOfHour(timestamp) as hour,
    src_ip,
    dst_ip,
    sum(bytes) as total_bytes,
    count() as flow_count
FROM flows_local
GROUP BY hour, src_ip, dst_ip;

-- Query the view instead of raw table (much faster)
SELECT * FROM flows_hourly_mv WHERE hour >= '2026-03-01';
```

**Test queries on small dataset first**:
```sql
-- Develop query with LIMIT
SELECT ... FROM flows WHERE timestamp > now() - INTERVAL 1 HOUR LIMIT 1000;

-- Once optimized, remove LIMIT for production
SELECT ... FROM flows WHERE timestamp > now() - INTERVAL 1 DAY;
```

### Comparison Database Selection

**InfluxDB chosen over Prometheus** for this project because:
- **Better cardinality handling**: ~1M series vs Prometheus ~100K
- **More direct comparison**: Both are time-series databases
- **Easier to demonstrate**: Tag model similar to Prometheus labels
- **Still struggles**: High-cardinality NetFlow data exceeds InfluxDB limits
- **Proves point**: ClickHouse's unlimited cardinality advantage

**Key architectural difference**:
- **InfluxDB**: Tag/field separation, tags fully indexed (cardinality penalty)
- **ClickHouse**: All columns treated equally, no cardinality penalty
- **Result**: ClickHouse handles NetFlow's billions of unique combinations effortlessly

### Data Generation for Testing

**Use realistic distributions** (mimics production traffic):
```python
# Pareto distribution (80/20 rule)
# 20% of IPs generate 80% of traffic
def generate_pareto_ips(total_ips, alpha=1.16):
    return pareto.rvs(alpha, size=total_ips)

# Log-normal for bytes/packets (most flows small, few large)
bytes = lognormal(mean=log(320*1024), sigma=1.5)
```

**Cardinality targets for meaningful testing**:
- **10K src IPs, 50K dst IPs**: Basic testing (~500M combinations)
- **50K src IPs, 200K dst IPs**: **RECOMMENDED** (~10B combinations)
- **100K src IPs, 500K dst IPs**: Extreme testing (~50B combinations)

**Dataset sizing for limited storage** (based on project experience):
- **10M records**: ~5GB total (basic functionality)
- **50M records**: ~23GB total (**RECOMMENDED for comparisons**)
- **100M records**: ~46GB total (requires cleanup: `docker system prune -a`)

### Operational Lessons

**Authentication required** in all commands:
```bash
# Always pass --password
docker exec clickhouse01 clickhouse-client --password admin --query "..."

# Without password: Authentication failed error
docker exec clickhouse01 clickhouse-client --query "..."  # ❌ Fails
```

**Verification after schema changes**:
```sql
-- Verify table created
SELECT count(*) FROM system.tables 
WHERE database = 'netflow' AND name = 'flows_local';
-- Expected: 1

-- Check indexes
SELECT * FROM system.data_skipping_indices WHERE table = 'flows_local';

-- Verify data ingested
SELECT count(), min(timestamp), max(timestamp) FROM netflow.flows_local;
```

**Internal Docker network sufficient** for single-host setup:
```yaml
# No need for complex networking
networks:
  clickhouse_network:
    driver: bridge  # Simple and works
```
---

## Review Checklist

Before considering work complete, verify:

- [ ] Code follows simplicity principle (no unnecessary complexity)
- [ ] Scripts are modular and single-purpose
- [ ] All files have proper headers/comments
- [ ] Configuration is externalized (`.env`, not hard-coded)
- [ ] Prerequisites documented clearly (not coded as validation)
- [ ] Scripts are idempotent (can run multiple times safely)
- [ ] Documentation is updated with manual verification steps
- [ ] Examples are provided for non-obvious usage
- [ ] No secrets committed (passwords, keys, etc.)
- [ ] Paths are configurable, not hard-coded
- [ ] Validation overhead minimized - trust documented prerequisites

---

## Resources and References

### ClickHouse Documentation
- Official docs: https://clickhouse.com/docs
- System tables: https://clickhouse.com/docs/en/operations/system-tables
- Configuration reference: https://clickhouse.com/docs/en/operations/configuration-files

### Best Practices
- Shell scripting guide: https://google.github.io/styleguide/shellguide.html
- SQL style guide: https://www.sqlstyle.guide/
- Docker best practices: https://docs.docker.com/develop/dev-best-practices/

---

## Changelog
- 2026-03-16: Added ClickHouse-Specific Insights section with practical lessons learned
- 2026-03-16: Updated comparison database from Prometheus to InfluxDB
- 2026-03-06: Initial version - Core principles and standards established

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
  - If a bash script can do it, don't write Python

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
# Good: Explicit error messages and cleanup
function ingest_data() {
    local data_file=$1
    
    if [[ ! -f "$data_file" ]]; then
        echo "ERROR: Data file not found: $data_file" >&2
        return 1
    fi
    
    if ! curl -f -X POST ...; then
        echo "ERROR: Ingestion failed for $data_file" >&2
        return 1
    fi
    
    echo "SUCCESS: Ingested $data_file"
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
# Include basic validation at start of scripts
function validate_environment() {
    local required_vars=("CLICKHOUSE_HOST" "DATA_DIR")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "ERROR: Required variable $var not set" >&2
            exit 1
        fi
    done
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

# No error checking
docker exec clickhouse01 clickhouse-client --query "$SQL"
# What if container doesn't exist?

# Hard-coded paths
cat /home/user/my-data/flows.json | ...

# Mixed concerns
# Script that: starts cluster, creates schema, ingests data, runs tests
```

### ✅ Do This Instead
```bash
# Explicit error handling
if ! curl -f http://clickhouse:8123/; then
    echo "ERROR: ClickHouse not responding" >&2
    exit 1
fi

# Clear variable names
CLICKHOUSE_MASTER_HOST="clickhouse01"
CLICKHOUSE_HTTP_PORT="8123"

# Defensive programming
if ! docker exec clickhouse01 clickhouse-client --query "$SQL"; then
    echo "ERROR: Query failed: $SQL" >&2
    exit 1
fi

# Configurable paths
DATA_DIR="${DATA_DIR:-./data}"
cat "${DATA_DIR}/flows.json" | ...

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
- Add: `set -euo pipefail` at start
- Add: Error messages with `>&2`
- Add: Exit code checks after each command

---

## Review Checklist

Before considering work complete, verify:

- [ ] Code follows simplicity principle (no unnecessary complexity)
- [ ] Scripts are modular and single-purpose
- [ ] All files have proper headers/comments
- [ ] Configuration is externalized (`.env`, not hard-coded)
- [ ] Error handling is explicit
- [ ] Scripts are idempotent (can run multiple times safely)
- [ ] Documentation is updated
- [ ] Examples are provided for non-obvious usage
- [ ] No secrets committed (passwords, keys, etc.)
- [ ] Paths are configurable, not hard-coded

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
- 2026-03-06: Initial version - Core principles and standards established

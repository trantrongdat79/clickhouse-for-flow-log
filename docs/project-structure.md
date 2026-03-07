# ClickHouse NetFlow Analytics - Project Structure

This document describes the recommended directory structure and organization for the ClickHouse high-cardinality NetFlow analytics project.

---

## Directory Layout

```
clickhouse-for-flow-log/
│
├── README.md                           # Project overview, quick start guide
├── .gitignore                          # Git ignore patterns (data files, secrets)
├── .env.example                        # Environment variables template
│
├── docker/                             # Docker infrastructure
│   ├── docker-compose.yml              # Main compose file (all services)
│   ├── docker-compose.dev.yml          # Development overrides
│   ├── docker-compose.prod.yml         # Production settings
│   ├── .env                            # Environment variables (gitignored)
│   │
│   ├── clickhouse/                     # ClickHouse container configs
│   │   ├── Dockerfile                  # Custom ClickHouse image (if needed)
│   │   ├── initdb.d/                   # Initialization SQL scripts
│   │   │   ├── 01-create-cluster.sql
│   │   │   ├── 02-create-tables.sql
│   │   │   └── 03-create-users.sql
│   │   └── docker-entrypoint.sh        # Custom entrypoint script
│   │
│   ├── zookeeper/                      # ZooKeeper configs
│   │   └── zoo.cfg                     # ZooKeeper configuration
│   │
│   ├── prometheus/                     # Prometheus configs
│   │   ├── prometheus.yml              # Scrape configs
│   │   └── rules/                      # Alert rules
│   │       └── clickhouse.rules.yml
│   │
│   └── grafana/                        # Grafana configs
│       ├── provisioning/
│       │   ├── datasources/            # Auto-provisioned datasources
│       │   │   ├── clickhouse.yml
│       │   │   └── prometheus.yml
│       │   └── dashboards/             # Auto-provisioned dashboards
│       │       └── dashboards.yml
│       └── dashboards/                 # Dashboard JSON files
│           ├── netflow-traffic.json
│           ├── cluster-health.json
│           └── performance-comparison.json
│
├── clickhouse-config/                  # ClickHouse XML configurations
│   ├── config.d/                       # Server configuration overrides
│   │   ├── remote_servers.xml          # Cluster topology definition
│   │   ├── macros.xml.template         # Macros template (per-node)
│   │   ├── ssl.xml                     # SSL/TLS configuration
│   │   ├── logging.xml                 # Logging configuration
│   │   └── storage.xml                 # Storage policies
│   │
│   └── users.d/                        # User configuration
│       ├── users.xml                   # User definitions
│       ├── quotas.xml                  # Query quotas
│       └── profiles.xml                # Settings profiles
│
├── sql/                                # SQL schema and queries
│   ├── schema/                         # DDL statements
│   │   ├── 01-flows-local.sql          # ReplicatedMergeTree table
│   │   ├── 02-flows-distributed.sql    # Distributed table
│   │   ├── 03-materialized-views.sql   # Aggregation views
│   │   └── 04-skip-indexes.sql         # Bloom filter indexes
│   │
│   ├── security/                       # Security configuration
│   │   ├── 01-roles.sql                # Create roles
│   │   ├── 02-users.sql                # Create users
│   │   ├── 03-row-policies.sql         # Row-level security
│   │   └── 04-grants.sql               # Permission grants
│   │
│   ├── queries/                        # Sample queries
│   │   ├── benchmark_queries_clickhouse.sql
│   │   ├── top_talkers.sql
│   │   ├── traffic_matrix.sql
│   │   └── anomaly_detection.sql
│   │
│   └── maintenance/                    # Maintenance queries
│       ├── optimize_tables.sql         # Manual optimization
│       ├── check_replication.sql       # Replication health
│       └── cleanup_old_partitions.sql  # Partition management
│
├── data-gen/                           # Data generation scripts
│   ├── requirements.txt                # Python dependencies
│   ├── generate_flows.py               # Main data generator
│   ├── generate_flows_parallel.py      # Parallel generator (faster)
│   ├── config.yaml                     # Generation parameters
│   │
│   ├── utils/                          # Helper modules
│   │   ├── __init__.py
│   │   ├── ip_generator.py             # IP address generation
│   │   ├── distribution.py             # Statistical distributions
│   │   └── converter.py                # Format converters
│   │
│   ├── output/                         # Generated data (gitignored)
│   │   ├── flows_001.json
│   │   ├── flows_002.json
│   │   └── ...
│   │
│   └── convert_to_prometheus.py        # Convert to Prometheus format
│
├── scripts/                            # Operational scripts
│   ├── setup/                          # Setup and initialization
│   │   ├── 01-setup-cluster.sh         # Initial cluster setup
│   │   ├── 02-generate-macros.sh       # Generate per-node macros
│   │   ├── 03-init-schema.sh           # Execute DDL scripts
│   │   └── 04-load-test-data.sh        # Load sample data
│   │
│   ├── ingestion/                      # Data ingestion
│   │   ├── ingest_parallel.sh          # Parallel ingestion
│   │   ├── ingest_streaming.sh         # Streaming ingestion
│   │   └── monitor_ingestion.sh        # Monitor insertion rate
│   │
│   ├── benchmark/                      # Performance benchmarking
│   │   ├── benchmark_ingest_clickhouse.sh
│   │   ├── benchmark_ingest_prometheus.sh
│   │   ├── benchmark_queries.sh
│   │   ├── load_test.sh                # Concurrent query test
│   │   └── measure_storage.sh          # Storage metrics
│   │
│   ├── backup/                         # Backup and recovery
│   │   ├── backup_full.sh              # Full backup
│   │   ├── backup_incremental.sh       # Incremental backup
│   │   ├── restore.sh                  # Restore from backup
│   │   └── test_recovery.sh            # Recovery testing
│   │
│   ├── testing/                        # Operational testing
│   │   ├── test_replication.sh         # Replication lag test
│   │   ├── test_failover.sh            # Failover test
│   │   ├── test_security.sh            # RBAC and policy tests
│   │   └── test_quotas.sh              # Quota enforcement test
│   │
│   ├── monitoring/                     # Monitoring helpers
│   │   ├── check_cluster_health.sh     # Cluster status check
│   │   ├── check_replication_lag.sh    # Replication monitoring
│   │   ├── check_disk_usage.sh         # Disk space monitoring
│   │   └── export_metrics.sh           # Export metrics to file
│   │
│   └── maintenance/                    # Maintenance operations
│       ├── optimize_tables.sh          # Run OPTIMIZE TABLE
│       ├── cleanup_logs.sh             # Clean old logs
│       ├── drop_old_partitions.sh      # Drop old partitions
│       └── rebalance_shards.sh         # Rebalance data
│
├── tests/                              # Automated tests
│   ├── unit/                           # Unit tests
│   │   └── test_data_generator.py
│   │
│   ├── integration/                    # Integration tests
│   │   ├── test_cluster_setup.py
│   │   ├── test_replication.py
│   │   └── test_queries.py
│   │
│   └── performance/                    # Performance tests
│       ├── test_ingestion_throughput.py
│       └── test_query_latency.py
│
├── docs/                               # Documentation
│   ├── architecture.md                 # System architecture
│   ├── setup-guide.md                  # Setup instructions
│   ├── operational-runbook.md          # Operations guide
│   ├── query-guide.md                  # Query examples
│   ├── troubleshooting.md              # Common issues
│   ├── performance-tuning.md           # Tuning recommendations
│   ├── security-guide.md               # Security best practices
│   ├── backup-recovery.md              # Backup procedures
│   ├── project-structure.md            # This file
│   ├── report-template-outline.md      # Report template
│   │
│   ├── diagrams/                       # Architecture diagrams
│   │   ├── cluster-topology.png
│   │   ├── data-flow.png
│   │   └── replication-model.png
│   │
│   └── screenshots/                    # Dashboard screenshots
│       ├── grafana-netflow.png
│       └── grafana-cluster.png
│
├── data/                               # Persistent data (gitignored)
│   ├── clickhouse01/                   # Node 1 data
│   ├── clickhouse02/                   # Node 2 data
│   ├── clickhouse03/                   # Node 3 data
│   ├── clickhouse04/                   # Node 4 data
│   ├── zookeeper01/                    # ZK node 1 data
│   ├── zookeeper02/                    # ZK node 2 data
│   ├── zookeeper03/                    # ZK node 3 data
│   ├── prometheus/                     # Prometheus data
│   └── grafana/                        # Grafana data
│
├── logs/                               # Log files (gitignored)
│   ├── clickhouse/
│   ├── zookeeper/
│   ├── prometheus/
│   └── ingestion/
│
├── backups/                            # Backup storage (gitignored)
│   ├── clickhouse/
│   │   ├── full_backup_20260306/
│   │   └── incremental_backup_20260306/
│   └── zookeeper/
│
├── benchmark-results/                  # Benchmark outputs
│   ├── ingestion_clickhouse.csv
│   ├── ingestion_prometheus.csv
│   ├── queries_clickhouse.csv
│   ├── queries_prometheus.csv
│   └── load_test_results.json
│
└── presentation/                       # Project presentation
    ├── slides.pdf                      # Presentation slides
    ├── demo-script.md                  # Live demo script
    └── video/                          # Demo recordings
        └── demo.mp4
```

---

## File Descriptions

### Root Level Files

#### README.md
```markdown
# ClickHouse NetFlow Analytics Project

## Quick Start
```bash
# Clone repository
git clone <repo-url>

# Copy environment template
cp .env.example docker/.env

# Start cluster
cd docker
docker-compose up -d

# Initialize schema
cd ../scripts/setup
./01-setup-cluster.sh
```

## Project Structure
See docs/project-structure.md for detailed layout.
```

#### .gitignore
```
# Data files
data-gen/output/*.json
data-gen/output/*.txt
data/
logs/
backups/

# Environment
.env
*.env.local

# Python
__pycache__/
*.pyc
.venv/
venv/

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Benchmark results
benchmark-results/*.csv
benchmark-results/*.json
```

#### .env.example
```bash
# ClickHouse Configuration
CLICKHOUSE_VERSION=24.1
CLICKHOUSE_PASSWORD=secure_password_here
CLICKHOUSE_HTTP_PORT=8123
CLICKHOUSE_NATIVE_PORT=9000

# Cluster Configuration
CLUSTER_NAME=netflow_cluster
SHARD_COUNT=2
REPLICA_COUNT=2

# ZooKeeper Configuration
ZOOKEEPER_VERSION=3.8
ZK_TICK_TIME=2000

# Prometheus Configuration
PROMETHEUS_VERSION=v2.48.0
PROMETHEUS_PORT=9090

# Grafana Configuration
GRAFANA_VERSION=10.2.3
GRAFANA_PORT=3000
GRAFANA_ADMIN_PASSWORD=admin_password_here

# Data Generation
TOTAL_RECORDS=250000000
UNIQUE_SRC_IPS=100000
UNIQUE_DST_IPS=500000
TIME_RANGE_DAYS=60

# Backup Configuration
BACKUP_RETENTION_DAYS=7
BACKUP_LOCATION=/backups
```

---

## Configuration Files

All configuration files have been initialized with placeholder content and TODO comments indicating their purpose. See the actual files in the project directories:

- **Docker configuration**: `docker/docker-compose.yml`
- **ClickHouse cluster topology**: `clickhouse-config/config.d/remote_servers.xml`
- **Node-specific macros**: `clickhouse-config/config.d/macros.xml.template`
- **Environment variables**: `.env.example` (copy to `docker/.env`)

Each file contains detailed comments explaining:
- Purpose and usage
- Configuration options
- Scaling considerations (minimal vs full cluster)
- Related files and dependencies

Refer to individual files for implementation details and TODO items.

---

## Script Organization

### Setup Scripts Flow

1. **01-setup-cluster.sh** - Starts all containers, waits for health
2. **02-generate-macros.sh** - Creates node-specific macro configs
3. **03-init-schema.sh** - Executes DDL (tables, views, indexes)
4. **04-load-test-data.sh** - Loads sample data for testing

### Benchmark Workflow

1. Generate data: `data-gen/generate_flows.py`
2. Ingest to ClickHouse: `scripts/ingestion/ingest_parallel.sh`
3. Convert to Prometheus format: `data-gen/convert_to_prometheus.py`
4. Ingest to Prometheus: `scripts/benchmark/benchmark_ingest_prometheus.sh`
5. Run query benchmarks: `scripts/benchmark/benchmark_queries.sh`
6. Collect results: `benchmark-results/*.csv`

---

## Data Flow

```
┌────────────────┐
│  Data          │
│  Generator     │  generate_flows.py
└───────┬────────┘
        │
        ├─────────────┐
        │             │
        v             v
┌───────────────┐   ┌──────────────────┐
│  JSONEachRow  │   │  Prometheus      │
│  Files        │   │  Exposition      │
│  (CH)         │   │  Format (Prom)   │
└───────┬───────┘   └────────┬─────────┘
        │                    │
        v                    v
┌───────────────┐   ┌──────────────────┐
│  ClickHouse   │   │  Prometheus      │
│  Cluster      │   │  (via Pushgw)    │
│  (Distributed)│   │                  │
└───────┬───────┘   └────────┬─────────┘
        │                    │
        └──────────┬─────────┘
                   │
                   v
           ┌───────────────┐
           │   Grafana     │
           │  Dashboards   │
           └───────────────┘
```

---

## Naming Conventions

### Files
- **SQL files**: `01-descriptive-name.sql` (numbered for execution order)
- **Scripts**: `descriptive_name.sh` (snake_case)
- **Python**: `descriptive_name.py` (snake_case)
- **Configs**: `service-name.yml` or `config-type.xml`

### Database Objects
- **Tables**: `lowercase_snake_case` (e.g., `flows_local`, `flows_distributed`)
- **Views**: `*_mv` suffix for materialized views (e.g., `flows_hourly_mv`)
- **Roles**: `lowercase_role` (e.g., `readonly_analyst`)
- **Users**: `lowercase` (e.g., `alice`, `bob`)

### Docker Services
- **ClickHouse nodes**: `clickhouse01`, `clickhouse02`, etc.
- **ZooKeeper nodes**: `zookeeper01`, `zookeeper02`, etc.
- **Other services**: `prometheus`, `grafana` (lowercase)

---

## Development Workflow

### Initial Setup
```bash
# 1. Clone and configure
git clone <repo>
cd clickhouse-for-flow-log
cp .env.example docker/.env
# Edit docker/.env with your settings

# 2. Start infrastructure
cd docker
docker-compose up -d

# 3. Initialize cluster
cd ../scripts/setup
./01-setup-cluster.sh
./02-generate-macros.sh
./03-init-schema.sh

# 4. Verify cluster health
./scripts/monitoring/check_cluster_health.sh
```

### Data Generation and Ingestion
```bash
# 1. Generate synthetic data
cd data-gen
python generate_flows.py --records 10000000 --output output/

# 2. Ingest into ClickHouse
cd ../scripts/ingestion
./ingest_parallel.sh ../../data-gen/output/flows_*.json

# 3. Monitor ingestion
./monitor_ingestion.sh
```

### Running Benchmarks
```bash
cd scripts/benchmark

# 1. ClickHouse ingestion benchmark
./benchmark_ingest_clickhouse.sh > ../../benchmark-results/ingest_ch.log

# 2. Prometheus ingestion benchmark (smaller dataset)
./benchmark_ingest_prometheus.sh > ../../benchmark-results/ingest_prom.log

# 3. Query benchmarks
./benchmark_queries.sh > ../../benchmark-results/queries.log

# 4. Load test
./load_test.sh > ../../benchmark-results/load_test.log
```

### Testing Operations
```bash
cd scripts/testing

# Test replication
./test_replication.sh

# Test failover
./test_failover.sh

# Test security
./test_security.sh

# Test backups
cd ../backup
./backup_full.sh
./test_recovery.sh
```

---

## Documentation Standards

### Code Comments
- **SQL**: Use `--` for single-line, `/* */` for multi-line
- **Bash**: Use `#` for comments, include script header with purpose
- **Python**: Use docstrings for functions/classes

### Script Headers
```bash
#!/bin/bash
# Script: benchmark_queries.sh
# Purpose: Run performance benchmark comparing ClickHouse and Prometheus
# Usage: ./benchmark_queries.sh [--iterations N]
# Author: Your Name
# Date: 2026-03-06
```

### README Files
- Every major directory should have a README.md
- Include purpose, usage examples, and dependencies

---

## Maintenance

### Daily
- Monitor cluster health
- Check replication lag
- Review logs for errors

### Weekly
- Run incremental backups
- Analyze query performance
- Review disk usage

### Monthly
- Test backup restoration
- Update documentation
- Review and optimize queries

---

## Security Best Practices

### Secrets Management
- Never commit `.env` files
- Use environment variables for passwords
- Rotate credentials regularly

### Network Security
- Use internal Docker network for services
- Expose only necessary ports
- Enable SSL/TLS for production

### Access Control
- Implement RBAC from day one
- Use row-level policies for multi-tenancy
- Set appropriate quotas per user

---

## Troubleshooting

### Common Issues

**Cluster won't start**
```bash
# Check ZooKeeper first
docker logs zookeeper01
docker exec zookeeper01 zkServer.sh status

# Check ClickHouse logs
docker logs clickhouse01
```

**Replication lag**
```bash
# Check replication status
docker exec clickhouse01 clickhouse-client --query "SELECT * FROM system.replicas"
```

**Out of disk space**
```bash
# Check disk usage
docker exec clickhouse01 clickhouse-client --query "
SELECT 
    name, 
    formatReadableSize(total_space) as total,
    formatReadableSize(free_space) as free
FROM system.disks
"

# Manual cleanup
./scripts/maintenance/drop_old_partitions.sh
```

---

## Appendix: Useful Commands

### Docker Management
```bash
# Start cluster
docker-compose up -d

# Stop cluster
docker-compose down

# View logs
docker logs -f clickhouse01

# Execute command
docker exec clickhouse01 clickhouse-client --query "SELECT version()"

# Resource usage
docker stats
```

### ClickHouse Queries
```sql
-- Check cluster topology
SELECT * FROM system.clusters WHERE cluster = 'netflow_cluster';

-- Check table sizes
SELECT 
    table,
    formatReadableSize(sum(bytes_on_disk)) as size
FROM system.parts
WHERE active
GROUP BY table;

-- Monitor queries
SELECT 
    user,
    query_id,
    elapsed,
    formatReadableSize(memory_usage) as memory
FROM system.processes;

-- Replication status
SELECT * FROM system.replicas WHERE table = 'flows_local';
```

---

This structure provides organization for a production-quality project suitable for an Advanced Database Systems course, with clear separation of concerns and comprehensive documentation.

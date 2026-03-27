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
├── QUICKSTART_GUIDE.md                 # Quick start instructions
├── SYSTEM_REQUIREMENTS.md              # System requirements
│
├── docker/                             # Docker infrastructure
│   ├── docker-compose.yml              # Main compose file (clustered: 2 CH nodes, 3 ZK nodes)
│   ├── .env                            # Environment variables (gitignored)
│   ├── clickhouse/                     # ClickHouse configurations
│   │   ├── clickhouse-config/          # Configuration files
│   │   │   ├── config.d/               # Server configuration overrides
│   │   │   │   ├── remote_servers.xml  # Cluster configuration (2 replicas)
│   │   │   │   ├── macros.xml.template # Node-specific variables template
│   │   │   │   ├── network.xml         # Network settings
│   │   │   │   └── storage.xml         # Storage policies (if exists)
│   │   │   ├── users.d/                # User configuration
│   │   │   │   ├── users.xml           # User definitions
│   │   │   │   └── default-user.xml    # Default user settings
│   │   │   ├── node01/                 # Node 1 specific config
│   │   │   │   └── macros.xml          # Node 1 macros (replica=replica1)
│   │   │   └── node02/                 # Node 2 specific config
│   │   │       └── macros.xml          # Node 2 macros (replica=replica2)
│   │   ├── initdb.d/                   # Initialization scripts
│   │   │   └── 01-create-databases.sql # Initial database setup
│   │   └── README.md                   # ClickHouse configuration guide
│   ├── influxdb/                       # InfluxDB configurations
│   │   └── scripts/                    # Initialization scripts
│   │       └── README.md               # InfluxDB setup notes
│   ├── grafana/                        # Grafana configurations
│   │   ├── provisioning/               # Auto-provisioning configs
│   │   │   ├── datasources/            # Datasource definitions
│   │   │   │   ├── clickhouse.yml      # ClickHouse datasource
│   │   │   │   └── influxdb.yml        # InfluxDB datasource
│   │   │   └── dashboards/             # Dashboard provisioning
│   │   │       └── dashboards.yml      # Dashboard config
│   │   └── dashboards/                 # Dashboard JSON files
│   │       ├── system-health.json      # System metrics dashboard
│   │       └── VPC Flow Log Dashboard.json  # Main flow analytics dashboard
│   └── README.md                       # Docker setup guide
│
├── sql/                                # SQL schema and queries
│   ├── schema/                         # DDL statements
│   │   ├── 01-flows-local.sql          # MergeTree table (for single-node benchmarking)
│   │   ├── 02-flows-replicated.sql     # ReplicatedMergeTree table (for replicated cluster)
│   │   ├── 03-flows-distributed.sql    # Distributed table (optional - for sharding scenarios)
│   ├── queries/                        # Sample analytical queries
│   │   ├── verify_data.sql             # Data quality verification
│   │   ├── benchmark_queries.sql       # Performance testing queries
│   │   ├── top_talkers.sql             # Top-N queries
│   │   ├── traffic_matrix.sql          # High-cardinality aggregations
│   │   └── geo_analysis.sql            # Geographic queries
│   ├── security/                       # Security-related SQL
│   │   └── 01-roles.sql                # RBAC role definitions (optional)
│   └── maintenance/                    # Maintenance queries
│       ├── optimize_tables.sql         # Manual optimization
│       └── cleanup_old_partitions.sql  # Partition management
│
├── data-gen/                           # Data generation scripts
│   ├── requirements.txt                # Python dependencies
│   ├── generate_flows.py               # Main data generator
│   ├── config.yaml                     # Generation parameters
│   ├── convert_to_influxdb.py          # Convert to InfluxDB format
│   ├── README.md                       # Data generation guide
│   └── output/                         # Generated data (gitignored)
│       └── flows_001.json              # Sample generated flow data
│
├── scripts/                            # Operational scripts
│   ├── setup/                          # Setup and initialization
│   │   ├── 01-init-schema.sh           # Execute DDL scripts
│   │   ├── 02-load-test-data.sh        # Load sample data (optional)
│   │   └── setup-cluster.sh            # Start containers (optional)
│   ├── ingestion/                      # Data ingestion
│   │   ├── ingest_clickhouse.py        # ClickHouse ingestion script
│   │   ├── ingest_influxdb.py          # InfluxDB ingestion script
│   │   ├── ingest_comparison.sh        # Compare ingestion performance
│   │   └── monitor_ingestion.sh        # Monitor insertion rate (optional)
│   ├── query/                          # Query benchmarking
│   │   ├── query_clickhouse.py         # ClickHouse query benchmark
│   │   ├── query_influxdb.py           # InfluxDB query benchmark
│   │   ├── query_comparison.sh         # Compare query performance
│   │   └── README.md                   # Query benchmark guide
│   ├── maintenance/                    # Maintenance and testing scripts
│   │   ├── test_components.sh          # Component integration test
│   │   ├── test_replication.sh         # Replication testing (lag, failover)
│   │   ├── test_backup_restore.sh      # Backup & restore testing
│   │   ├── backup_cluster.sh           # Cluster-wide backup (optional)
│   │   ├── check_cluster_health.sh     # Cluster status check (optional)
│   │   └── check_disk_usage.sh         # Disk space monitoring (optional)
│   ├── security/                       # Security testing scripts
│   │   ├── test_security_rbac.sh       # RBAC security testing
│   │   ├── test_security_row_policy.sh # Row-level policy testing
│   │   └── test_security_quotas.sh     # Query quota testing
│   └── cleanup_all.sh                  # Cleanup all data and containers
│
├── docs/                               # Documentation
│   ├── AGENTS.md                       # AI agent guidelines
│   ├── project-structure.md            # This file - complete project reference
│   ├── influxdb-comparison.md          # InfluxDB comparison guide (optional)
│   └── ideas.md                        # User notes (optional)
│
├── data/                               # Persistent data (gitignored)
│   └── grafana/                        # Grafana data (bind mount)
│       ├── alerting/                   # Alert configurations
│       ├── csv/                        # CSV data (optional)
│       ├── dashboards/                 # User dashboards
│       ├── plugins/                    # Grafana plugins
│       │   ├── grafana-clickhouse-datasource/  # ClickHouse plugin
│       │   ├── netsage-sankey-panel/   # Sankey diagram plugin
│       │   └── yesoreyeram-infinity-datasource/  # Infinity datasource
│       └── png/                        # Dashboard screenshots (optional)
│
├── logs/                               # Log files (gitignored, bind mounted)
│   ├── clickhouse01/                   # ClickHouse node 1 logs
│   ├── clickhouse02/                   # ClickHouse node 2 logs
│   ├── influxdb/                       # InfluxDB logs
│   └── grafana/                        # Grafana logs
│
├── backups/                            # Backup storage (gitignored)
│   └── clickhouse/                     # ClickHouse cluster backups
│
├── benchmark-results/                  # Benchmark outputs
│   ├── ingest/                         # Ingestion benchmarks
│   │   ├── ingest-clickhouse-output.txt
│   │   ├── ingest-influxdb-output.txt
│   │   └── ingest-comparison-results.txt
│   └── query/                          # Query benchmarks
│       ├── query-clickhouse-output.txt
│       ├── query-influxdb-output.txt
│       └── query-comparison-results.txt
│
└── report/                             # Project reports and analysis (optional)
```

### Cluster Architecture

**ClickHouse Cluster: `netflow_cluster`** (Replication-focused setup)
- **Topology**: 2 replicas for high availability and data redundancy
- **Node 1** (`clickhouse01`):
  - HTTP Port: 8123
  - Native Port: 9000
  - Inter-server: 9009
  - Role: Replica 1 (primary or follower via ZooKeeper coordination)
- **Node 2** (`clickhouse02`):
  - HTTP Port: 8124
  - Native Port: 9001
  - Inter-server: 9010
  - Role: Replica 2 (primary or follower via ZooKeeper coordination)

**ZooKeeper Ensemble (Coordination)**
- **ZooKeeper 1**: Port 2181
- **ZooKeeper 2**: Port 2182
- **ZooKeeper 3**: Port 2183
- **Purpose**: Replication coordination, metadata storage, leader election, consistency management

**Table Strategy**
- `flows_local`: MergeTree table for single-node benchmarking (no replication)
- `flows_replicated`: ReplicatedMergeTree table for replicated cluster (main production table)
- `flows_distributed`: Distributed table (optional - only needed for multi-shard scenarios)

### Naming Conventions

**Files**:
- SQL files: `01-descriptive-name.sql` (numbered for execution order)
- Scripts: `descriptive_name.sh` (snake_case)
- Python: `descriptive_name.py` (snake_case)
- Configs: `service-name.yml` or `config-type.xml`

**Database Objects**:
- Tables: `lowercase_snake_case` (e.g., `flows_local`, `flows_replicated`)
- Views: `*_mv` suffix for materialized views (e.g., `flows_hourly_mv`)
- Database: `netflow` (dedicated, not `default`)

**Docker Services**:
- ClickHouse: `clickhouse01`, `clickhouse02`
- ZooKeeper: `zookeeper01`, `zookeeper02`, `zookeeper03`
- InfluxDB: `influxdb`
- Grafana: `grafana`

---
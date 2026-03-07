# ClickHouse High-Cardinality NetFlow Analytics System - Implementation Plan

## Project Overview

This plan guides a 2-person team through building a production-like ClickHouse cluster demonstrating replication, sharding, security, and performance comparison with Prometheus over 4 weeks. The system will ingest 10-100GB of synthetic NetFlow data in JSONEachRow format, using a full cluster topology (2 shards × 2 replicas + 3 ZooKeeper) with Grafana visualization. Priority: replication/sharding first, then security, backup/recovery, and performance benchmarking.

**Expected Deliverables:**
- Docker-compose orchestration for 8-container cluster
- Synthetic NetFlow dataset generator (JSONEachRow format)
- Configured ClickHouse cluster with replication and sharding
- Security implementation (RBAC, row-level policies, quotas)
- Backup/restore procedures with testing
- Performance comparison framework (ClickHouse vs Prometheus)
- Grafana dashboards for visualization and monitoring
- Documentation covering architecture and operational procedures

---

## Week 1: Infrastructure Foundation & Data Preparation

### 1. Create project structure
Create directories for docker configs, data generation scripts, SQL schemas, and documentation:
- `docker/` - compose files and container configurations
- `clickhouse-config/` - ClickHouse XML configs (cluster topology, users, macros)
- `data-gen/` - NetFlow data generator scripts
- `sql/` - DDL statements for tables, views, policies
- `grafana/` - dashboard JSON exports
- `docs/` - architecture diagrams and runbooks

### 2. Implement docker-compose.yml
Define infrastructure with:
- 4 ClickHouse servers: `clickhouse01-shard1-replica1`, `clickhouse02-shard1-replica2`, `clickhouse03-shard2-replica1`, `clickhouse04-shard2-replica2`
- 3 ZooKeeper nodes: `zookeeper01`, `zookeeper02`, `zookeeper03`
- 1 Grafana instance for visualization
- 1 Prometheus instance for metrics collection
- Networks: `clickhouse-net` (internal cluster), `frontend-net` (external access)
- Volumes: persistent storage for each ClickHouse data directory, ZooKeeper data, Grafana dashboards

### 3. Configure ClickHouse cluster topology
Via `remote_servers.xml`:
- Define 2 shards with 2 replicas each
- ZooKeeper ensemble connection strings
- Internal replication enabled
- Random sharding key for balanced distribution

### 4. Create macros configuration
For each ClickHouse node:
- `{shard}` macro: "01" or "02" 
- `{replica}` macro: "replica1" or "replica2"
- Used in ReplicatedMergeTree engine parameters

### 5. Design NetFlow schema
Optimized for high-cardinality data:
- Table: `flows_local` (ReplicatedMergeTree on each node)
- Table: `flows_distributed` (Distributed engine as query interface)
- Fields: timestamp, src_ip (IPv4), dst_ip, src_port, dst_port, protocol, bytes (Delta+LZ4), packets (Delta+LZ4), tcp_flags, flow_duration
- Partition by `toYYYYMMDD(timestamp)` for daily partitions
- Order by `(timestamp, cityHash64(src_ip), cityHash64(dst_ip))` - time-first for range queries
- Skip indexes: bloom_filter on src_ip and dst_ip for point queries
- Compression codecs: DoubleDelta+LZ4 for timestamp, Delta+LZ4 for counters, LZ4 for IPs

### 6. Develop NetFlow data generator
In Python:
- Generate 10-100GB of realistic flows (50-500 million records)
- JSONEachRow format: `{"timestamp":"2026-02-24 10:00:00","src_ip":"192.168.1.1",...}\n`
- Distributions: 80/20 for top talkers (simulate real-world skew), random IPs from RFC1918 ranges, weighted protocols (TCP 70%, UDP 25%, other 5%)
- Time range: 30-90 days of historical data with hourly buckets
- Cardinality targets: ~100K unique src_ip, ~500K unique dst_ip, ~1M unique port combinations
- Output: split into 1GB files for parallel ingestion

### 7. Verify infrastructure startup
And basic connectivity:
- All containers healthy and networked
- ClickHouse inter-server replication ports (9009) accessible
- ZooKeeper ensemble formed with leader election
- Prometheus scraping ClickHouse metrics exporters
- Grafana connects to ClickHouse datasource

**Week 1 Deliverables:** Working docker-compose cluster, NetFlow schema designed, 10-100GB test dataset generated

---

## Week 2: Replication, Sharding & Data Ingestion

### 8. Create ReplicatedMergeTree tables
On all 4 ClickHouse nodes:
- SSH/exec into each container
- Execute DDL for `flows_local`: `ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/flows', '{replica}') PARTITION BY toYYYYMMDD(timestamp) ORDER BY (...)`
- Verify table creation in `system.tables` and `system.replicas`
- Confirm ZooKeeper paths created in `/clickhouse/tables/01/flows` and `/clickhouse/tables/02/flows`

### 9. Create Distributed table
For unified query interface:
- On any node: `CREATE TABLE flows_distributed AS flows_local ENGINE = Distributed('cluster_name', 'default', 'flows_local', rand())`
- Random sharding key `rand()` distributes writes evenly
- Test: INSERT into distributed table should route to random shards

### 10. Implement batch data ingestion pipeline
Script: `ingest.sh` using ClickHouse HTTP API:
```bash
cat flow_data_001.json | curl -X POST 'http://clickhouse01:8123/?query=INSERT%20INTO%20flows_distributed%20FORMAT%20JSONEachRow' --data-binary @-
```
- Parallel ingestion: run 4 concurrent processes (one per file chunk)
- Monitor: `SELECT count(*) FROM flows_distributed` and `system.parts` for merge activity
- Target: 100K-500K rows/second throughput
- Verify: data distributed across shards (`SELECT _shard_num, count(*) FROM flows_distributed GROUP BY _shard_num`)

### 11. Test replication functionality
- INSERT data directly into one replica: `INSERT INTO flows_local VALUES (...)`
- Query second replica: data should appear automatically
- Check replication lag: `SELECT * FROM system.replicas WHERE table='flows_local'`
- Simulate replica failure: stop one container, verify queries still work via other replica

### 12. Create materialized views
For common aggregations:
- Hourly traffic summary: `CREATE MATERIALIZED VIEW flows_hourly_mv ENGINE = SummingMergeTree() PARTITION BY toYYYYMM(hour) ORDER BY (hour, src_ip) AS SELECT toStartOfHour(timestamp) as hour, src_ip, sum(bytes) as total_bytes, sum(packets) as total_packets FROM flows_local GROUP BY hour, src_ip`
- Top talkers by day: similar pattern with different time granularity
- Protocol distribution: aggregate by protocol field
- Purpose: accelerate dashboard queries

### 13. Set up query monitoring
- Enable query_log: `SET log_queries = 1`
- Prometheus queries for ClickHouse metrics: query latency, inserted rows/sec, merge throughput
- Grafana dashboard: "ClickHouse Cluster Health" showing inserts, queries, merges, replication lag

### 14. Optimize initial data loading
- Disable replication during bulk load: `SET insert_quorum = 0`
- Use async inserts: `SET async_insert = 1`
- After load complete: run `OPTIMIZE TABLE flows_local FINAL` on one replica per shard (DO NOT run on all replicas simultaneously)

**Week 2 Deliverables:** Fully replicated and sharded cluster with 10-100GB data ingested, materialized views, monitoring dashboards

---

## Week 3: Security Hardening & Backup/Recovery

### 15. Implement RBAC with user roles
- SQL: `CREATE ROLE readonly_analyst` with `GRANT SELECT ON default.flows_distributed TO readonly_analyst`
- SQL: `CREATE ROLE data_engineer` with `GRANT SELECT, INSERT ON default.* TO data_engineer`
- SQL: `CREATE ROLE admin_role` with `GRANT ALL ON *.* TO admin_role`
- Create users: `CREATE USER alice IDENTIFIED BY SHA256_HASH 'hash...' DEFAULT ROLE readonly_analyst`
- Test: connect as alice, attempt INSERT (should fail), attempt SELECT (should succeed)

### 16. Configure row-level security policies
- Policy: users see only flows from their assigned network segment
- Example: `CREATE ROW POLICY network_filter ON flows_distributed FOR SELECT USING toIPv4(src_ip) BETWEEN toIPv4('10.0.0.0') AND toIPv4('10.255.255.255') TO alice`
- Create multiple policies for different network ranges
- Test: query as different users, verify filtered results

### 17. Set up query quotas
To prevent resource exhaustion:
- XML config in `users.d/quotas.xml`: max execution time (30 seconds), max rows to read (10M), max concurrent queries (5), max memory usage (10GB)
- Assign quotas to roles: `ALTER USER alice SETTINGS max_execution_time = 30`
- Test: run expensive query exceeding limits, verify it's killed with quota error

### 18. Enable SSL/TLS for client connections
- Generate self-signed certificates (or use Let's Encrypt for production)
- Configure ClickHouse `config.d/ssl.xml`: paths to certificate, key, and CA
- Update Grafana datasource to use HTTPS port 8443
- Test: connection without SSL should fail, with SSL should succeed

### 19. Configure network access restrictions
- Edit `users.xml`: `<alice><networks><ip>10.0.0.0/8</ip></networks></alice>`
- Block public internet access to native protocol port 9000
- Expose only HTTP port 8123 via reverse proxy (optional: add Nginx)
- Test: connect from allowed/disallowed networks

### 20. Implement backup strategy
Using clickhouse-backup:
- Install clickhouse-backup utility in each container
- Configuration: S3 bucket (or local volume) for backup storage, compression enabled (zstd), retention policy (7 daily backups)
- Create initial backup: `clickhouse-backup create full_backup_20260224`
- Verify backup contents: check metadata, data files, schema

### 21. Test backup and recovery procedures
- Simulate disaster: drop table `DROP TABLE flows_local`
- Restore from backup: `clickhouse-backup restore full_backup_20260224`
- Verify: row counts match pre-disaster state
- Document recovery time objective (RTO): measure minutes to restore 10GB, 50GB, 100GB
- Test incremental backup: create new data, run incremental, verify delta stored

### 22. Back up ZooKeeper metadata
Critical for cluster recovery:
- ZooKeeper snapshot export: `zkCli.sh` commands to dump /clickhouse paths
- Store snapshots alongside ClickHouse backups
- Document restore sequence: ZooKeeper first, then ClickHouse schema, then data

### 23. Create security audit dashboard
In Grafana:
- Queries: failed login attempts (`system.query_log` where `exception != ''`), queries by user, quotas exceeded
- Alerts: unusual query patterns, failed authentication spikes

**Week 3 Deliverables:** Production-ready security (RBAC, row policies, quotas, SSL), tested backup/recovery procedures, audit dashboards

---

## Week 4: Performance Benchmarking & Finalization

### 24. Set up Prometheus for metrics ingestion
For comparison:
- Configure Prometheus to scrape synthetic "flow metrics" from custom exporter
- Translate NetFlow data to Prometheus metrics: `flow_bytes_total{src_ip="...", dst_ip="...", protocol="..."}` (note: this creates cardinality explosion, which is the point)
- Ingest subset of NetFlow data: 1/10th volume or limited time range (Prometheus will struggle with high cardinality)
- Monitor Prometheus memory usage and cardinality warnings

### 25. Benchmark data ingestion performance
- ClickHouse: measure rows/sec, compression ratio (raw size / stored size), CPU/memory during ingestion
- Prometheus: measure samples/sec, memory growth, scrape success rate
- Use identical 10GB dataset subset for fair comparison
- Tool: `clickhouse-benchmark` for ClickHouse, Prometheus metrics for Prometheus
- Document: ClickHouse should show 10-100x higher throughput and compression

### 26. Design representative query workload
- Q1: Point query - specific IP in time range: `SELECT * FROM flows_distributed WHERE src_ip='192.168.1.100' AND timestamp > now() - INTERVAL 1 DAY`
- Q2: Aggregation - top 10 talkers: `SELECT src_ip, sum(bytes) FROM flows_distributed WHERE timestamp > now() - INTERVAL 7 DAY GROUP BY src_ip ORDER BY sum(bytes) DESC LIMIT 10`
- Q3: Complex analytics - traffic matrix: `SELECT src_ip, dst_ip, sum(bytes) FROM flows_distributed GROUP BY src_ip, dst_ip`
- Q4: Percentile query: `SELECT quantiles(0.5, 0.95, 0.99)(bytes) FROM flows_distributed`
- Q5: Time-series aggregation: `SELECT toStartOfHour(timestamp) as hour, sum(bytes) FROM flows_distributed GROUP BY hour ORDER BY hour`
- Prometheus equivalents: attempt same queries using PromQL (some won't be possible)

### 27. Execute performance benchmarks
- ClickHouse: run each query 10 times, record p50/p95/p99 latency
- Prometheus: run equivalent queries, note which queries fail or timeout
- Concurrent queries: simulate 10, 20, 50 users with `clickhouse-benchmark --concurrency=10`
- Record: query latency, queries per second (QPS), CPU/memory/disk I/O utilization
- Cardinality test: query with millions of unique combinations (ClickHouse handles, Prometheus OOM)

### 28. Create comprehensive Grafana dashboards
- Dashboard 1: "NetFlow Traffic Analysis" - time-series charts, top talkers, protocol distribution, geographic maps (if enriched with GeoIP)
- Dashboard 2: "ClickHouse Cluster Monitoring" - insert rate, query latency, merge activity, replication lag, disk usage
- Dashboard 3: "Performance Comparison" - side-by-side ClickHouse vs Prometheus metrics
- Dashboard 4: "Security Audit" - user activity, quota usage, failed queries
- Use ClickHouse datasource plugin for Grafana, template variables for dynamic filtering

### 29. Document architecture and operations
- Architecture diagram: containers, networks, data flow (ingestion → sharding → replication → query)
- README: project overview, quick start (docker-compose up), data generation, sample queries
- Runbook: backup/restore procedures, adding nodes to cluster, troubleshooting replication lag
- Performance report: benchmark results with charts, analysis of ClickHouse advantages for high-cardinality data
- Security guide: user management, policy creation, SSL certificate renewal

### 30. Prepare demo script and presentation materials
- Live demo: start cluster, show replication (insert on node1, query node2), execute sharded queries, demonstrate security features
- Failover demo: stop one replica, show queries continue working
- Performance demo: run same query on ClickHouse and Prometheus, compare execution time
- Backup demo: backup → disaster → restore flow
- Slides: abstract summary, architecture diagrams, benchmark charts, lessons learned

**Week 4 Deliverables:** Performance benchmark report (ClickHouse vs Prometheus), production-ready Grafana dashboards, complete documentation, demo-ready system

---

## Verification Checklist

Run comprehensive validation before final delivery:

### 1. Functional tests
- Insert 1M new records via distributed table, verify across all replicas
- Stop one ClickHouse node, confirm queries still succeed
- Execute all 5 query types, verify results match expected cardinality
- Test user permissions (alice readonly, bob data_engineer, admin full control)

### 2. Performance tests
- Ingestion: 100K+ rows/sec sustained throughput
- Queries: p95 latency <1 second for simple aggregations, <10 seconds for complex analytics
- Compression: 10-30x ratio on NetFlow data
- Prometheus comparison: ClickHouse 10-100x faster on high-cardinality queries

### 3. Operational tests
- Backup → delete table → restore completes in <10 minutes for 10GB
- ZooKeeper restart doesn't break cluster
- ClickHouse rolling restart (one node at a time) maintains availability
- Grafana dashboards load in <3 seconds

### 4. Commands to validate

```bash
# Cluster health
docker-compose ps
docker exec clickhouse01 clickhouse-client --query "SELECT * FROM system.clusters"

# Data distribution
docker exec clickhouse01 clickhouse-client --query "SELECT _shard_num, count(*) FROM flows_distributed GROUP BY _shard_num"

# Replication status
docker exec clickhouse01 clickhouse-client --query "SELECT * FROM system.replicas WHERE table='flows_local'"

# Benchmark query
docker exec clickhouse01 clickhouse-benchmark --query "SELECT count(*) FROM flows_distributed WHERE src_ip='192.168.1.100'" --iterations 10

# Backup test
docker exec clickhouse01 clickhouse-backup create test_backup
docker exec clickhouse01 clickhouse-backup list
```

### 5. Documentation checklist
- All docker-compose commands documented
- Schema DDL statements in SQL files
- Data generator usage examples
- Backup/restore runbook tested
- Grafana dashboard JSONs exported
- Performance benchmark spreadsheet completed

---

## Key Technical Decisions

- **Cluster topology**: Full 2×2 replication/sharding to demonstrate production patterns, not simplified single-node
- **Data format**: JSONEachRow balances flexibility (easy generation, human-readable) with performance (faster than CSV)
- **Visualization**: Grafana chosen for mature ClickHouse plugin and extensive documentation
- **Prometheus scope**: Full comparison despite mismatch (NetFlow in Prometheus) to highlight ClickHouse's cardinality advantages
- **Backup tool**: clickhouse-backup for production-readiness instead of manual snapshots
- **Partitioning**: Daily partitions (not hourly) suitable for 10-100GB over 30-90 days
- **Primary key order**: `(timestamp, hash(src_ip), hash(dst_ip))` prioritizes time-range queries over IP lookups
- **Security priorities**: RBAC and row-level policies over encryption at rest (more demonstrable in demo)

---

## Additional Notes

### Data Volume Considerations
- Target: 10-100GB of NetFlow data (50-500 million records)
- Distribution: 30-90 days of historical data
- Cardinality: ~100K unique source IPs, ~500K unique destination IPs, ~1M unique port combinations

### Team Allocation Suggestions
With 2 people, consider dividing work:
- **Week 1-2**: Both work on infrastructure setup and data generation (pair programming recommended for Docker/ClickHouse config)
- **Week 3**: Person A focuses on security (RBAC, policies, SSL), Person B on backup/recovery
- **Week 4**: Person A on Prometheus integration and benchmarking, Person B on Grafana dashboards and documentation
- Final 2-3 days: Both collaborate on testing, polishing, and preparing demo

### Risk Mitigation
- **ZooKeeper complexity**: Start with single ZK node if 3-node ensemble causes issues, upgrade later
- **Data generation time**: Begin generating data in Week 1, run overnight if needed
- **Prometheus cardinality issues**: Limit Prometheus test to smaller dataset (1-10GB) if memory constraints arise
- **Time pressure**: If behind schedule, simplify to 1 shard × 2 replicas (still demonstrates replication)

### Stretch Goals (if ahead of schedule)
- Kafka integration for streaming ingestion
- GeoIP enrichment for geographic visualization
- Query result cache optimization
- Multi-cluster federation
- Custom ClickHouse function for IP subnet aggregation

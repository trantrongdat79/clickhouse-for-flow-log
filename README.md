# ClickHouse NetFlow Analytics Project

## Overview

This project demonstrates ClickHouse's capabilities for storing and analyzing high-cardinality network flow (NetFlow) data. Built as part of an Advanced Database Systems course, it compares ClickHouse's performance against traditional time-series databases.

## QuickStart

**New Users**: See [QUICKSTART_GUIDE.md](QUICKSTART_GUIDE.md) for detailed step-by-step instructions.

```bash
# 1. Clone and setup
git clone <repo-url>
cd clickhouse-for-flow-log
pip3 install -r requirements.txt
cp .env.example docker/.env

# 2. Start all services (ClickHouse, InfluxDB, Grafana)
cd docker && docker compose up -d

# 3. Initialize schema
cd ../scripts/setup && ./01-init-schema.sh

# 4. Generate and ingest data
cd ../../data-gen && python3 generate_flows.py --records 100000 --output output/
cd ../scripts/ingestion && ./ingest_clickhouse.sh ../../data-gen/output
./ingest_influxdb.sh ../../data-gen/output

# 5. Access Grafana at http://localhost:3000 (admin/admin_change_me)
```

## Project Structure

See [docs/project-structure.md](docs/project-structure.md) for detailed organization.

## Key Features

- **Distributed ClickHouse cluster**: Replication and sharding demonstration
- **High-cardinality data**: 100K+ unique IPs, millions of combinations
- **Performance benchmarking**: Ingestion, query, and storage comparisons
- **Operational testing**: Replication, failover, backup/recovery
- **Security implementation**: RBAC, row-level policies, quotas

## Documentation

### Getting Started
- **[QUICKSTART_GUIDE.md](QUICKSTART_GUIDE.md)** - Step-by-step setup guide (START HERE!)
- **[SYSTEM_REQUIREMENTS.md](SYSTEM_REQUIREMENTS.md)** - System requirements and verification
- [requirements.txt](requirements.txt) - Python dependencies

### Project Documentation
- [Architecture Overview](docs/architecture.md) - System design and rationale
- [Setup Guide](docs/setup-guide.md) - Installation and configuration
- [Project Structure](docs/project-structure.md) - Directory organization
- [AI Guidelines](docs/AGENTS.md) - Development standards
- [Report Outline](docs/report-template-outline.md) - Academic report template

### Component Documentation
- [ClickHouse Configuration](docker/clickhouse/README.md) - Config structure and setup
- [InfluxDB Scripts](docker/influxdb/scripts/README.md) - Why scripts directory is empty

### Maintenance
- [scripts/cleanup_all.sh](scripts/cleanup_all.sh) - Reset project to clean state

## Requirements

See [SYSTEM_REQUIREMENTS.md](SYSTEM_REQUIREMENTS.md) for detailed requirements.

**Quick checklist:**
- Docker 20.10+ & Docker Compose 2.0+
- Python 3.8+ with pip
- 4GB RAM, 20GB disk space
- Ports 3000, 8086, 8123, 9000 available
- 16GB+ RAM recommended
- 100GB+ disk space
- Python 3.8+ (for data generation)

## Dataset

- **Scale**: 750MB - 75GB (configurable)
- **Records**: 2.5M - 250M flows
- **Time range**: 60 days
- **Cardinality**: 100K source IPs, 500K destination IPs
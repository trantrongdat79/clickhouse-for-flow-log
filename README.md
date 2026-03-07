# ClickHouse NetFlow Analytics Project

## Overview

This project demonstrates ClickHouse's capabilities for storing and analyzing high-cardinality network flow (NetFlow) data. Built as part of an Advanced Database Systems course, it compares ClickHouse's performance against traditional time-series databases.

## QuickStart

```bash
# 1. Clone and configure
git clone <repo-url>
cd clickhouse-for-flow-log
cp .env.example docker/.env
# Edit docker/.env with your settings

# 2. Start infrastructure
cd docker
docker-compose up -d

# 3. Initialize cluster
cd ../scripts/setup
./01-setup-cluster.sh

# 4. Verify cluster health
../monitoring/check_cluster_health.sh
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

- [Architecture Overview](docs/architecture.md) - System design and rationale
- [Setup Guide](docs/setup-guide.md) - Installation and configuration
- [Project Structure](docs/project-structure.md) - Directory organization
- [AI Guidelines](docs/AGENTS.md) - Development standards
- [Report Outline](docs/report-template-outline.md) - Academic report template

## Requirements

- Docker & Docker Compose
- 16GB+ RAM recommended
- 100GB+ disk space
- Python 3.8+ (for data generation)

## Dataset

- **Scale**: 750MB - 75GB (configurable)
- **Records**: 2.5M - 250M flows
- **Time range**: 60 days
- **Cardinality**: 100K source IPs, 500K destination IPs

## License

[Specify license]

## Contributors

[Team member names]

## Acknowledgments

- ClickHouse documentation and community
- Advanced Database Systems course, [University name]

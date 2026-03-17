# Quick Start Guide

This guide will help you get the ClickHouse NetFlow Analytics project up and running in ~15 minutes.

## Prerequisites

Before starting, make sure you have:
- Docker and Docker Compose installed
- Python 3.8+ with pip
- At least 4GB RAM and 20GB disk space
- Ports 3000, 8086, 8123, 9000 available

See [SYSTEM_REQUIREMENTS.md](SYSTEM_REQUIREMENTS.md) for detailed requirements.

## Step 1: Clone and Setup (2 minutes)

```bash
# Clone the repository (if not already done)
cd /path/to/your/workspace
git clone <repository-url> clickhouse-for-flow-log
cd clickhouse-for-flow-log

# Install Python dependencies
python3 -m venv .venv
pip3 install -r requirements.txt

# Create environment file
cp .env.example docker/.env
# Optionally edit docker/.env to customize passwords/ports
```

## Step 2: Start All Services (3 minutes)

```bash
# Navigate to docker directory
cd docker

# Start all services (ClickHouse, InfluxDB, Grafana)
docker compose up -d

# Wait for services to be healthy (check status)
docker compose ps

# Wait until all services show "healthy" status
# This may take 30-60 seconds
watch -n 2 'docker compose ps'
```

Expected output when ready:
```
NAME         STATUS                    PORTS
clickhouse01 Up About a minute (healthy)  8123/tcp, 9000/tcp, 9009/tcp
influxdb     Up About a minute (healthy)  8086/tcp
grafana      Up About a minute (healthy)  3000/tcp
```

Press `Ctrl+C` to exit the watch command.

## Step 3: Initialize ClickHouse Schema (1 minute)

```bash
# Navigate to setup scripts
cd ../scripts/setup

# Initialize the ClickHouse database schema
./02-init-schema.sh

# Verify schema creation
docker exec -it clickhouse01 clickhouse-client --query "SHOW TABLES FROM netflow"
```

Expected output:
```
flows_local
flows_distributed
flows_mv_hourly
...
```

## Step 4: Generate Test Data (2 minutes)

```bash
# Navigate to data generation directory
cd ../../data-gen

# Generate small test dataset (100,000 records)
python3 generate_flows.py --records 100000 --output output/

# This should take 5-10 seconds
# Output will be in data-gen/output/flows_*.json
```

## Step 5: Ingest Data into ClickHouse (2 minutes)

```bash
# Navigate to ingestion scripts
cd ../scripts/ingestion

# Ingest data into ClickHouse
./ingest_clickhouse.sh ../../data-gen/output

# Wait for completion (should take 10-30 seconds)
```

Expected output:
```
========================================
ClickHouse Data Ingestion
========================================
...
✓ Ingestion Complete!
Records inserted: 100,000
```

## Step 6: Ingest Data into InfluxDB (3 minutes)

```bash
# Still in scripts/ingestion directory

# Ingest data into InfluxDB
./ingest_influxdb.sh ../../data-gen/output

# This may take 1-2 minutes for 100K records
```

Expected output:
```
==================================================
InfluxDB Data Ingestion
==================================================
...
✓ Ingestion Complete!
Records inserted: 100,000
```

## Step 7: Verify Data (1 minute)

### Verify ClickHouse
```bash
# Check record count
docker exec -it clickhouse01 clickhouse-client --query \
  "SELECT count() FROM netflow.flows_local"

# View sample data
docker exec -it clickhouse01 clickhouse-client --query \
  "SELECT * FROM netflow.flows_local LIMIT 5 FORMAT Pretty"
```

### Verify InfluxDB
```bash
# Using InfluxDB CLI
docker exec -it influxdb influx query \
  'from(bucket:"flows") |> range(start: -1d) |> limit(n: 5)' \
  --org netflow \
  --token my-super-secret-auth-token
```

## Step 8: Access Grafana (1 minute)

```bash
# Open Grafana in your browser
echo "Grafana: http://localhost:3000"
echo "Username: admin"
echo "Password: admin_change_me (or check docker/.env)"
```

1. Open http://localhost:3000 in your browser
2. Login with admin/admin_change_me
3. Navigate to Dashboards
4. You should see pre-configured dashboards for ClickHouse and InfluxDB

## Quick Testing Checklist

- [ ] All Docker containers are running and healthy
- [ ] ClickHouse has tables created (flows_local, flows_distributed)
- [ ] ClickHouse has data (100K records)
- [ ] InfluxDB has data (100K records)
- [ ] Grafana is accessible at http://localhost:3000
- [ ] Grafana shows data sources (ClickHouse and InfluxDB)

## What's Next?

### View Query Examples
```bash
cd sql/queries
cat examples.sql
```

### Run Benchmarks
```bash
cd scripts/benchmark
./compare_databases.sh
```

### Generate More Data
```bash
cd data-gen
# Generate 10 million records
python3 generate_flows.py --records 10000000 --output output/large_test
```

### Monitor Cluster Health
```bash
cd scripts/monitoring
./check_cluster_health.sh
```

## Common Issues & Solutions

### Services won't start
```bash
# Check logs
cd docker
docker compose logs clickhouse
docker compose logs influxdb
docker compose logs grafana

# Common fix: remove old volumes
docker compose down -v
docker compose up -d
```

### Port conflicts
```bash
# Check what's using the ports
sudo netstat -tulpn | grep -E ':(8123|9000|8086|3000)'

# Option 1: Stop conflicting service
# Option 2: Change ports in docker/.env
```

### Permission errors
```bash
# Fix Docker permissions
sudo usermod -aG docker $USER
# Then logout and login again
```

### ClickHouse schema not created
```bash
# Manual schema creation
cd scripts/setup
./02-init-schema.sh

# Or run SQL manually
docker exec -it clickhouse01 clickhouse-client < ../../sql/schema/01-flows-local.sql
```

### Python module not found
```bash
# Install dependencies
pip3 install -r requirements.txt

# Or install specific package
pip3 install influxdb-client
```

## Cleaning Up

To completely reset the environment:

```bash
# Navigate to project root
cd /path/to/clickhouse-for-flow-log

# Run cleanup script (will be created)
./scripts/cleanup_all.sh

# Or manually:
cd docker
docker compose down -v  # Remove containers and volumes
rm -rf ../data/*        # Remove data
rm -rf ../logs/*        # Remove logs
rm -rf ../data-gen/output/*  # Remove generated data
```

## Getting Help

- Check [README.md](README.md) for project overview
- See [docs/](docs/) for detailed documentation
- Review [SYSTEM_REQUIREMENTS.md](SYSTEM_REQUIREMENTS.md) for prerequisites
- Check container logs: `docker compose logs <service_name>`

## Summary of Commands

For reference, here's the complete sequence:

```bash
# Setup
cd clickhouse-for-flow-log
pip3 install -r requirements.txt
cp .env.example docker/.env

# Start services
cd docker && docker compose up -d

# Initialize schema
cd ../scripts/setup && ./02-init-schema.sh

# Generate and ingest data
cd ../../data-gen && python3 generate_flows.py --records 100000 --output output/
cd ../scripts/ingestion && ./ingest_clickhouse.sh ../../data-gen/output
./ingest_influxdb.sh ../../data-gen/output

# Access Grafana
# Open http://localhost:3000
```

That's it! You now have a fully functional NetFlow analytics system running with both ClickHouse and InfluxDB.

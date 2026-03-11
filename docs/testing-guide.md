# ClickHouse NetFlow Analytics - Testing Guide

This guide provides comprehensive instructions for testing the ClickHouse, Prometheus, and Grafana stack to ensure all components are working correctly.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Automated Testing](#automated-testing)
4. [Manual Testing](#manual-testing)
   - [ClickHouse Testing](#clickhouse-testing)
   - [Prometheus Testing](#prometheus-testing)
   - [Grafana Testing](#grafana-testing)
5. [Integration Testing](#integration-testing)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before running tests, ensure you have:

- Docker and Docker Compose installed
- At least 4GB of available RAM
- Ports 3000, 8123, 9000, and 9090 available
- `curl`, `wget`, or a web browser for UI testing

---

## Quick Start

### 1. Start the Stack

```bash
# Navigate to the docker directory
cd docker/

# Start all services
docker-compose up -d

# Wait for all services to be healthy (30-60 seconds)
docker-compose ps
```

Expected output:
```
NAME            IMAGE                                STATUS              PORTS
clickhouse01    clickhouse/clickhouse-server:24.1   Up (healthy)        0.0.0.0:8123->8123/tcp, 0.0.0.0:9000->9000/tcp
grafana         grafana/grafana:10.2.3              Up (healthy)        0.0.0.0:3000->3000/tcp
prometheus      prom/prometheus:v2.48.0             Up (healthy)        0.0.0.0:9090->9090/tcp
```

### 2. Run Automated Tests

```bash
# Navigate to the tests directory
cd ../tests/

# Run the test script
./test_components.sh
```

If all tests pass, you'll see:
```
========================================
Test Results Summary
========================================
Tests Run:    15
Tests Passed: 15
Tests Failed: 0

[PASS] All tests passed! ✓

[INFO] Access URLs:
  - ClickHouse: http://localhost:8123/play
  - Prometheus: http://localhost:9090
  - Grafana:    http://localhost:3000 (admin/admin_change_me)
```

---

## Automated Testing

The `test_components.sh` script performs comprehensive automated tests:

### Test Categories

1. **Docker Container Status**
   - Verifies all containers are running
   - Checks container health status

2. **ClickHouse Tests**
   - HTTP interface connectivity
   - Version query execution
   - Basic query execution
   - Database listing

3. **Prometheus Tests**
   - Health endpoint check
   - Readiness check
   - Targets configuration

4. **Grafana Tests**
   - Health endpoint check
   - API accessibility
   - Datasource endpoint check

5. **Network Connectivity**
   - Prometheus → ClickHouse connectivity
   - Grafana → ClickHouse connectivity
   - Grafana → Prometheus connectivity

### Running Specific Tests

You can modify the script to run specific test suites by commenting out sections in the `main()` function.

---

## Manual Testing

### ClickHouse Testing

#### Test 1: Web UI Access (Browser)

1. **Open ClickHouse Play Interface**
   - URL: http://localhost:8123/play
   - No authentication required by default

2. **Run a Test Query**
   ```sql
   SELECT version();
   ```
   Expected: Version number (e.g., `24.1.1.1`)

3. **Test System Tables**
   ```sql
   SHOW DATABASES;
   ```
   Expected output:
   ```
   INFORMATION_SCHEMA
   default
   information_schema
   netflow
   system
   ```

4. **Create a Test Table**
   ```sql
   CREATE TABLE IF NOT EXISTS test.sample (
       id UInt32,
       name String,
       created DateTime DEFAULT now()
   ) ENGINE = MergeTree()
   ORDER BY id;
   ```

5. **Insert Test Data**
   ```sql
   INSERT INTO test.sample (id, name) VALUES (1, 'test1'), (2, 'test2');
   ```

6. **Query Test Data**
   ```sql
   SELECT * FROM test.sample;
   ```
   Expected: 2 rows with test data

#### Test 2: Command Line Access (curl)

```bash
# Test ping
curl http://localhost:8123/ping
# Expected: Ok.

# Test version
curl "http://localhost:8123/?query=SELECT+version()"
# Expected: 24.1.1.1 (or similar)

# Test query
curl "http://localhost:8123/?query=SELECT+1"
# Expected: 1

# Show databases
curl "http://localhost:8123/?query=SHOW+DATABASES+FORMAT+TabSeparated"
# Expected: List of databases

# Insert data (JSONEachRow format)
echo '{"id":1,"name":"test"}' | curl -X POST "http://localhost:8123/?query=INSERT+INTO+test.sample+FORMAT+JSONEachRow" --data-binary @-

# Query data
curl "http://localhost:8123/?query=SELECT+*+FROM+test.sample+FORMAT+JSONEachRow"
```

#### Test 3: Docker Exec Access

```bash
# Connect to ClickHouse client
docker exec -it clickhouse01 clickhouse-client

# Run queries inside the client
clickhouse01 :) SELECT version();
clickhouse01 :) SHOW DATABASES;
clickhouse01 :) SELECT * FROM system.clusters;
clickhouse01 :) exit;
```

---

### Prometheus Testing

#### Test 1: Web UI Access (Browser)

1. **Open Prometheus UI**
   - URL: http://localhost:9090
   - No authentication required

2. **Check Targets**
   - Navigate to: Status → Targets
   - Verify all targets show "UP" status
   - Expected targets:
     - prometheus (localhost:9090)
     - clickhouse (clickhouse01:8123)
     - grafana (grafana:3000)

3. **Test Queries**
   - Go to Graph tab
   - Run: `up`
   - Expected: Shows all services with value `1` (up)

4. **Check ClickHouse Metrics**
   - Query: `up{job="clickhouse"}`
   - Expected: `1`

5. **Test Alert Rules**
   - Navigate to: Status → Rules
   - Verify alert rules are loaded from `clickhouse.rules.yml`

#### Test 2: Command Line Access (curl)

```bash
# Test health
curl http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy.

# Test readiness
curl http://localhost:9090/-/ready
# Expected: Prometheus is Ready.

# Query API
curl 'http://localhost:9090/api/v1/query?query=up'
# Expected: JSON response with status "success"

# Check targets
curl http://localhost:9090/api/v1/targets
# Expected: JSON with list of targets

# Check configuration
curl http://localhost:9090/api/v1/status/config
# Expected: Current Prometheus configuration
```

#### Test 3: Metrics Scraping

```bash
# Check if Prometheus is scraping ClickHouse metrics
curl 'http://localhost:9090/api/v1/query?query=up{job="clickhouse"}'

# Check scrape duration
curl 'http://localhost:9090/api/v1/query?query=scrape_duration_seconds{job="clickhouse"}'
```

---

### Grafana Testing

#### Test 1: Web UI Access (Browser)

1. **Login to Grafana**
   - URL: http://localhost:3000
   - Username: `admin`
   - Password: `admin_change_me` (or value from `.env`)

2. **Check Datasources**
   - Navigate to: Configuration → Data Sources
   - Verify two datasources are configured:
     - **ClickHouse** (Default)
     - **Prometheus**

3. **Test ClickHouse Datasource**
   - Go to ClickHouse datasource
   - Click "Save & Test"
   - Expected: "Data source is working" message

4. **Test Prometheus Datasource**
   - Go to Prometheus datasource
   - Click "Save & Test"
   - Expected: "Data source is working" message

5. **View Pre-Configured Dashboard**
   - Navigate to: Dashboards → Browse
   - Open "System Health Check" dashboard
   - Verify panels display data:
     - ClickHouse Version
     - ClickHouse Status (from Prometheus)

6. **Create Test Dashboard**
   - Click "+ Create" → Dashboard
   - Add new panel
   - Select ClickHouse datasource
   - Query: `SELECT version() as version`
   - Panel should display ClickHouse version

#### Test 2: API Access (curl)

```bash
# Test health (no auth required)
curl http://localhost:3000/api/health
# Expected: {"database":"ok","version":"..."}

# Test datasources (requires auth)
curl -u admin:admin_change_me http://localhost:3000/api/datasources
# Expected: JSON array with datasource configurations

# Test dashboards
curl -u admin:admin_change_me http://localhost:3000/api/dashboards/home
# Expected: Home dashboard JSON
```

#### Test 3: Plugin Installation Check

```bash
# Check if ClickHouse plugin is installed
docker exec grafana grafana-cli plugins ls | grep clickhouse
# Expected: grafana-clickhouse-datasource

# Check Grafana logs for plugin loading
docker logs grafana | grep -i clickhouse
# Should show plugin initialization messages
```

---

## Integration Testing

### Test 1: End-to-End Data Flow

This test verifies data can flow through the entire stack:

```bash
# 1. Insert data into ClickHouse
curl -X POST "http://localhost:8123/?query=CREATE+DATABASE+IF+NOT+EXISTS+test"

curl -X POST "http://localhost:8123/?query=CREATE+TABLE+IF+NOT+EXISTS+test.metrics+(timestamp+DateTime,+value+Float64)+ENGINE=MergeTree()+ORDER+BY+timestamp"

curl -X POST "http://localhost:8123/?query=INSERT+INTO+test.metrics+VALUES" \
  --data-binary "('2026-03-10 10:00:00', 42.5)"

# 2. Query from ClickHouse
curl "http://localhost:8123/?query=SELECT+*+FROM+test.metrics+FORMAT+JSONEachRow"

# 3. Create Grafana panel querying this data
# (Manual step: Create dashboard with query "SELECT * FROM test.metrics")

# 4. Verify Prometheus can scrape ClickHouse metrics
curl 'http://localhost:9090/api/v1/query?query=up{job="clickhouse"}'
```

### Test 2: Dashboard Data Visualization

1. **Open Grafana** (http://localhost:3000)
2. **Create New Dashboard**
3. **Add Panel with ClickHouse Query**
   ```sql
   SELECT 
       timestamp,
       value
   FROM test.metrics
   ORDER BY timestamp
   ```
4. **Add Panel with Prometheus Query**
   ```promql
   up{job="clickhouse"}
   ```
5. **Verify both panels display data**

### Test 3: Container Recovery

```bash
# Stop ClickHouse
docker stop clickhouse01

# Verify Prometheus shows target down
curl 'http://localhost:9090/api/v1/query?query=up{job="clickhouse"}'
# Expected: Result shows 0

# Restart ClickHouse
docker start clickhouse01

# Wait for health check
sleep 15

# Verify Prometheus shows target up
curl 'http://localhost:9090/api/v1/query?query=up{job="clickhouse"}'
# Expected: Result shows 1
```

---

## Troubleshooting

### Issue 1: Containers Not Starting

**Symptoms:**
- `docker-compose ps` shows containers as "Exited" or "Restarting"

**Solutions:**
```bash
# Check logs
docker-compose logs clickhouse
docker-compose logs prometheus
docker-compose logs grafana

# Check for port conflicts
sudo netstat -tlnp | grep -E '3000|8123|9000|9090'

# Verify .env configuration
cat docker/.env

# Remove volumes and restart
docker-compose down -v
docker-compose up -d
```

### Issue 2: ClickHouse Not Accessible

**Symptoms:**
- `curl http://localhost:8123/ping` fails
- Test script shows ClickHouse tests failing

**Solutions:**
```bash
# Check if container is running
docker ps | grep clickhouse

# Check ClickHouse logs
docker logs clickhouse01

# Check if port is exposed
docker port clickhouse01

# Try connecting from inside container
docker exec -it clickhouse01 clickhouse-client --query "SELECT 1"

# Verify configuration files
ls -la ../clickhouse-config/config.d/
ls -la ../clickhouse-config/users.d/
```

### Issue 3: Grafana Datasources Not Working

**Symptoms:**
- Grafana shows "Data source is failing"
- Dashboards show "No data"

**Solutions:**
```bash
# Check if plugins are installed
docker exec grafana grafana-cli plugins ls

# Check Grafana logs
docker logs grafana | tail -50

# Verify network connectivity
docker exec grafana wget -O- http://clickhouse01:8123/ping
docker exec grafana wget -O- http://prometheus:9090/-/healthy

# Restart Grafana with clean state
docker-compose restart grafana
```

### Issue 4: Prometheus Targets Down

**Symptoms:**
- Prometheus UI shows targets in "DOWN" state

**Solutions:**
```bash
# Check Prometheus configuration
docker exec prometheus cat /etc/prometheus/prometheus.yml

# Check Prometheus logs
docker logs prometheus | tail -50

# Verify network connectivity
docker exec prometheus wget -O- http://clickhouse01:8123/ping

# Test scrape endpoint manually
curl http://localhost:8123/metrics

# Reload Prometheus configuration
curl -X POST http://localhost:9090/-/reload
```

### Issue 5: Network Issues Between Containers

**Symptoms:**
- Services can't communicate with each other
- "Could not resolve host" errors

**Solutions:**
```bash
# Check Docker network
docker network ls
docker network inspect clickhouse-for-flow-log_netflow_network

# Verify all containers are on same network
docker inspect clickhouse01 | grep -A 20 Networks
docker inspect prometheus | grep -A 20 Networks
docker inspect grafana | grep -A 20 Networks

# Recreate network
docker-compose down
docker-compose up -d
```

### Issue 6: Test Script Failures

**Symptoms:**
- `./test_components.sh` shows failures
- Specific tests timeout

**Solutions:**
```bash
# Increase timeout in test script
export TIMEOUT=10
./test_components.sh

# Check if services are fully initialized
docker-compose ps
# Wait if status shows "starting" or "health: starting"

# Check if services are listening on correct ports
docker exec clickhouse01 netstat -tlnp
docker exec prometheus netstat -tlnp
docker exec grafana netstat -tlnp
```

---

## Performance Testing (Optional)

### Load Test ClickHouse

```bash
# Install clickhouse-benchmark (if not in container)
docker exec -it clickhouse01 bash

# Inside container
clickhouse-benchmark --host=localhost --port=9000 \
  --query="SELECT count() FROM system.numbers LIMIT 1000000" \
  --iterations=100 \
  --concurrency=10
```

### Monitor Resource Usage

```bash
# Watch Docker stats
docker stats

# Check ClickHouse system metrics
docker exec clickhouse01 clickhouse-client --query "
  SELECT 
    metric, 
    value 
  FROM system.metrics 
  WHERE metric LIKE '%Memory%'
"
```

---

## Test Checklist

Use this checklist to verify all components:

- [ ] All Docker containers are running and healthy
- [ ] ClickHouse HTTP interface responds to ping
- [ ] ClickHouse accepts and executes queries
- [ ] ClickHouse web UI (Play) is accessible
- [ ] Prometheus health endpoint returns "Healthy"
- [ ] Prometheus shows all targets as "UP"
- [ ] Prometheus UI is accessible and shows metrics
- [ ] Grafana login page is accessible
- [ ] Grafana datasources are configured and tested
- [ ] Grafana dashboards display data
- [ ] Network connectivity between all containers works
- [ ] Test script passes all automated tests
- [ ] Can insert and query data in ClickHouse
- [ ] Can query metrics from Prometheus
- [ ] Can visualize data in Grafana

---

## Next Steps

After verifying all components are working:

1. **Load Sample Data**: Use `data-gen/generate_flows.py` to create NetFlow data
2. **Create Schema**: Run SQL scripts in `sql/schema/` to create tables
3. **Configure Dashboards**: Import or create NetFlow-specific dashboards
4. **Run Benchmarks**: Execute performance comparison tests
5. **Review Documentation**: Read `docs/setup-guide.md` for advanced configuration

---

## Additional Resources

- [ClickHouse Documentation](https://clickhouse.com/docs)
- [Prometheus Documentation](https://prometheus.io/docs)
- [Grafana Documentation](https://grafana.com/docs)
- [Project Architecture](docs/architecture.md)
- [Troubleshooting Guide](docs/troubleshooting.md)

---

**Last Updated**: March 10, 2026  
**Version**: 1.0  
**Maintainer**: NetFlow Analytics Team

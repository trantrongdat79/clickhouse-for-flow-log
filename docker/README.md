# Docker Setup for ClickHouse NetFlow Analytics

This directory contains the Docker Compose setup for running ClickHouse, Prometheus, and Grafana for NetFlow analytics.

## Quick Start

### 1. Start All Services

```bash
# From the docker/ directory
docker-compose up -d
```

### 2. Verify Services

```bash
# Check container status
docker-compose ps

# All containers should show "Up (healthy)" status
```

### 3. Run Tests

```bash
# From project root
./tests/test_components.sh
```

### 4. Access Services

- **ClickHouse Web UI**: http://localhost:8123/play
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000
  - Username: `admin`
  - Password: `admin_change_me` (or check `.env` file)

## Configuration

### Environment Variables

The `.env` file contains all configuration parameters:

```bash
# Main service versions
CLICKHOUSE_VERSION=24.1
PROMETHEUS_VERSION=v2.48.0
GRAFANA_VERSION=10.2.3

# Ports
CLICKHOUSE_HTTP_PORT=8123
CLICKHOUSE_NATIVE_PORT=9000
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000

# Credentials
CLICKHOUSE_PASSWORD=secure_password_change_me
GRAFANA_ADMIN_PASSWORD=admin_change_me
```

### Directory Structure

```
docker/
├── docker-compose.yml          # Main compose file
├── .env                        # Environment variables
│
├── clickhouse/                 # ClickHouse configs
│   └── initdb.d/              # Initialization scripts
│
├── prometheus/                 # Prometheus configs
│   ├── prometheus.yml         # Main config
│   └── rules/                 # Alert rules
│       └── clickhouse.rules.yml
│
└── grafana/                    # Grafana configs
    ├── provisioning/
    │   ├── datasources/       # Auto-configured datasources
    │   │   ├── clickhouse.yml
    │   │   └── prometheus.yml
    │   └── dashboards/        # Dashboard providers
    │       └── dashboards.yml
    └── dashboards/            # Dashboard JSON files
        └── system-health.json
```

## Services

### ClickHouse

- **Image**: `clickhouse/clickhouse-server:24.1`
- **Ports**: 
  - 8123 (HTTP interface)
  - 9000 (Native protocol)
- **Data Volume**: `clickhouse_data`
- **Health Check**: `SELECT 1` query

### Prometheus

- **Image**: `prom/prometheus:v2.48.0`
- **Port**: 9090
- **Data Volume**: `prometheus_data`
- **Retention**: 30 days
- **Scrape Targets**: ClickHouse, Prometheus (self), Grafana

### Grafana

- **Image**: `grafana/grafana:10.2.3`
- **Port**: 3000
- **Data Volume**: `grafana_data`
- **Pre-installed Plugins**:
  - grafana-clickhouse-datasource
  - yesoreyeram-infinity-datasource
- **Auto-configured**:
  - ClickHouse datasource (default)
  - Prometheus datasource
  - System Health dashboard

## Common Commands

### Start Services

```bash
# Start in background
docker-compose up -d

# Start with logs
docker-compose up

# Start specific service
docker-compose up -d clickhouse
```

### Stop Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (CAUTION: deletes data)
docker-compose down -v
```

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f clickhouse
docker-compose logs -f prometheus
docker-compose logs -f grafana

# Last 50 lines
docker-compose logs --tail=50 clickhouse
```

### Restart Services

```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart clickhouse
```

### Execute Commands

```bash
# ClickHouse client
docker exec -it clickhouse01 clickhouse-client

# ClickHouse query
docker exec clickhouse01 clickhouse-client --query "SELECT version()"

# Bash in container
docker exec -it clickhouse01 bash
```

## Troubleshooting

### Ports Already in Use

If ports are already in use, modify them in `.env`:

```bash
CLICKHOUSE_HTTP_PORT=18123
PROMETHEUS_PORT=19090
GRAFANA_PORT=13000
```

Then restart:

```bash
docker-compose down
docker-compose up -d
```

### Containers Not Starting

Check logs for errors:

```bash
docker-compose logs clickhouse
```

Common issues:
- Insufficient memory (need at least 4GB RAM)
- Port conflicts
- Incorrect configuration files

### Network Issues

Verify network connectivity:

```bash
# Check network
docker network ls

# Inspect network
docker network inspect clickhouse-for-flow-log_netflow_network

# Test connectivity
docker exec prometheus wget -O- http://clickhouse01:8123/ping
```

### Reset Everything

To start fresh (deletes all data):

```bash
docker-compose down -v
docker-compose up -d
```

### Check Resource Usage

```bash
# Monitor all containers
docker stats

# Check disk usage
docker system df
```

## Testing

### Automated Testing

Run the comprehensive test script:

```bash
cd ../tests/
./test_components.sh
```

### Manual Testing

```bash
# Test ClickHouse
curl http://localhost:8123/ping

# Test Prometheus
curl http://localhost:9090/-/healthy

# Test Grafana
curl http://localhost:3000/api/health
```

See [docs/testing-guide.md](../docs/testing-guide.md) for detailed testing instructions.

## Data Persistence

Data is stored in Docker volumes:

- `clickhouse_data`: ClickHouse database files
- `clickhouse_logs`: ClickHouse log files
- `prometheus_data`: Prometheus time-series data
- `grafana_data`: Grafana dashboards and settings
- `grafana_logs`: Grafana log files

### Backup Volumes

```bash
# Create backup directory
mkdir -p ../backups

# Backup ClickHouse data
docker run --rm -v clickhouse-for-flow-log_clickhouse_data:/data -v $(pwd)/../backups:/backup alpine tar czf /backup/clickhouse-backup-$(date +%Y%m%d).tar.gz -C /data .

# Backup Grafana data
docker run --rm -v clickhouse-for-flow-log_grafana_data:/data -v $(pwd)/../backups:/backup alpine tar czf /backup/grafana-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Restore Volumes

```bash
# Restore ClickHouse data
docker run --rm -v clickhouse-for-flow-log_clickhouse_data:/data -v $(pwd)/../backups:/backup alpine tar xzf /backup/clickhouse-backup-YYYYMMDD.tar.gz -C /data

# Restore Grafana data
docker run --rm -v clickhouse-for-flow-log_grafana_data:/data -v $(pwd)/../backups:/backup alpine tar xzf /backup/grafana-backup-YYYYMMDD.tar.gz -C /data
```

## Security Notes

### Default Credentials

**IMPORTANT**: Change default passwords in `.env` before deploying to production:

```bash
CLICKHOUSE_PASSWORD=your_secure_password
GRAFANA_ADMIN_PASSWORD=your_secure_password
```

### Network Security

- Services communicate on internal Docker network `netflow_network`
- Only necessary ports are exposed to host
- For production, consider:
  - Using SSL/TLS
  - Restricting port access with firewall
  - Using Docker secrets for sensitive data

## Next Steps

After successfully starting the stack:

1. ✅ Verify all services are healthy
2. ✅ Run test script to confirm connectivity
3. 📊 Load sample data using `data-gen/generate_flows.py`
4. 🗄️ Create database schema from `sql/schema/`
5. 📈 Create custom Grafana dashboards
6. 🔍 Run performance benchmarks

## Additional Resources

- [Testing Guide](../docs/testing-guide.md) - Comprehensive testing instructions
- [Project Structure](../docs/project-structure.md) - Full project layout
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [Prometheus Documentation](https://prometheus.io/docs)
- [Grafana Documentation](https://grafana.com/docs)

---

**Need Help?**

Check the logs, review the testing guide, or see the troubleshooting section above.

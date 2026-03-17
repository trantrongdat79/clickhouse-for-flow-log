# InfluxDB Scripts Directory

## Why is this directory empty?

InfluxDB 2.x uses **environment variables** for automatic initialization, unlike ClickHouse which requires SQL scripts.

## How InfluxDB is initialized

The initialization is configured in `docker/docker-compose.yml` using these environment variables:

```yaml
environment:
  DOCKER_INFLUXDB_INIT_MODE: setup
  DOCKER_INFLUXDB_INIT_USERNAME: admin
  DOCKER_INFLUXDB_INIT_PASSWORD: admin_password_change_me
  DOCKER_INFLUXDB_INIT_ORG: netflow
  DOCKER_INFLUXDB_INIT_BUCKET: flows
  DOCKER_INFLUXDB_INIT_RETENTION: 30d
  DOCKER_INFLUXDB_INIT_ADMIN_TOKEN: my-super-secret-auth-token
```

When the InfluxDB container starts for the first time, it automatically:
1. Creates the organization (`netflow`)
2. Creates the bucket (`flows`) with 30-day retention
3. Generates the admin token for API access
4. Sets up the admin user

## When to use this directory

You can add shell scripts here if you need to:
- Create additional buckets
- Set up custom retention policies
- Configure advanced settings
- Create DBRP (Database/Retention Policy) mappings for InfluxDB 1.x compatibility

## Example script (optional)

If needed, create a script like `01-setup-additional-buckets.sh`:

```bash
#!/bin/bash
# This script runs after InfluxDB initialization

influx bucket create \
  --name metrics \
  --org netflow \
  --retention 90d \
  --token my-super-secret-auth-token
```

Make it executable: `chmod +x 01-setup-additional-buckets.sh`

Scripts run in alphabetical order (01-, 02-, etc.).

## Schema in InfluxDB

Unlike relational databases, InfluxDB is **schemaless**. The schema is defined implicitly when you write data:

- **Measurement**: Like a table name (e.g., "flows")
- **Tags**: Indexed string values (e.g., src_ip, dst_ip, protocol)
- **Fields**: Actual metrics (e.g., bytes, packets, duration)
- **Timestamp**: Time of the event

The schema is created automatically on first write. See `scripts/ingestion/ingest_influxdb.py` for how data is structured.

## See also

- [InfluxDB 2.x Setup Documentation](https://docs.influxdata.com/influxdb/v2.7/install/)
- [Docker Environment Variables](https://hub.docker.com/_/influxdb)
- Main ingestion script: `scripts/ingestion/ingest_influxdb.py`

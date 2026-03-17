# ClickHouse Configuration Directory Structure

This directory contains ClickHouse server configuration files organized into subdirectories.

## Directory Structure

```
clickhouse/
├── clickhouse-config/          # Main configuration directory
│   ├── config.d/              # Server configuration files
│   │   ├── macros.xml.template    # Node macros (shard, replica)
│   │   ├── network.xml            # Network settings
│   │   └── remote_servers.xml     # Cluster topology
│   └── users.d/               # User and profile settings
│       ├── default-user.xml       # Default user configuration
│       └── users.xml              # Profiles and quotas
└── initdb.d/                  # Database initialization scripts
    └── 01-create-databases.sql    # Creates netflow and test databases
```

## Configuration Files

### config.d/ - Server Configuration

These files are mounted to `/etc/clickhouse-server/config.d/` in the container.

- **macros.xml.template**: Defines cluster macros for replication
  - Used in `ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/flows', '{replica}')`
  - Must be generated per node with unique values
  - Template should be copied to `macros.xml` and customized

- **network.xml**: Network interface configuration
  - Allows connections from all interfaces (`0.0.0.0`)
  - Required for Grafana and external clients to connect

- **remote_servers.xml**: Cluster topology definition
  - Defines shards and replicas
  - Used for distributed queries
  - Required for `Distributed` engine tables

### users.d/ - User Configuration

These files are mounted to `/etc/clickhouse-server/users.d/` in the container.

- **default-user.xml**: Default user settings
  - Password: `admin` (change in production!)
  - Full access from any IP (::/0)
  - Access management enabled

- **users.xml**: Profiles and quotas
  - Performance settings (memory, threads, timeouts)
  - Query quotas and limits
  - Read-only profile for restricted access

### initdb.d/ - Initialization Scripts

These files are mounted to `/docker-entrypoint-initdb.d/` and run on first startup.

- **01-create-databases.sql**: Creates databases
  - Creates `netflow` database for flow data
  - Creates `test` database for testing
  - Only runs if databases don't exist

## Docker Mount Points

The `docker-compose.yml` mounts these directories:

```yaml
volumes:
  - ./clickhouse/clickhouse-config/config.d:/etc/clickhouse-server/config.d:ro
  - ./clickhouse/clickhouse-config/users.d:/etc/clickhouse-server/users.d:ro
  - ./clickhouse/initdb.d:/docker-entrypoint-initdb.d:ro
```

## Security Notes

⚠️ **WARNING**: The default configuration is for development/testing only!

For production:
1. Change default password in `users.d/default-user.xml`
2. Restrict network access in `config.d/network.xml`
3. Use environment variables for sensitive data
4. Enable SSL/TLS encryption
5. Set up proper user roles and quotas

## Customization

### For Single Node Setup
No changes needed - default configuration works.

### For Cluster Setup
1. Copy `macros.xml.template` to `macros.xml` for each node
2. Update `{SHARD_NUMBER}`, `{REPLICA_NAME}`, `{CLUSTER_NAME}` placeholders
3. Ensure `remote_servers.xml` matches your cluster topology
4. Update ZooKeeper settings if using replication

## See Also

- [ClickHouse Configuration Reference](https://clickhouse.com/docs/en/operations/configuration-files)
- [User Settings](https://clickhouse.com/docs/en/operations/settings/settings-users/)
- [Server Settings](https://clickhouse.com/docs/en/operations/server-configuration-parameters/settings/)
- Project schema: `sql/schema/`

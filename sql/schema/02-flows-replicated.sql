-- filepath: sql/schema/02-flows-replicated.sql
-- Purpose: Create replicated table for NetFlow data (high availability with 2 replicas)
-- Dependencies: ClickHouse cluster running, ZooKeeper ensemble, remote_servers.xml configured
-- Usage: Execute via clickhouse-client on ANY cluster node (will auto-replicate to all nodes)

-- Ensure netflow database exists on all nodes
CREATE DATABASE IF NOT EXISTS netflow ON CLUSTER netflow_cluster;

-- Drop existing table if running fresh setup
-- DROP TABLE IF EXISTS netflow.flows_replicated ON CLUSTER netflow_cluster;

-- Create replicated table on all cluster nodes
-- Data inserted on any node will automatically replicate to all other nodes
CREATE TABLE IF NOT EXISTS netflow.flows_replicated ON CLUSTER netflow_cluster
(
    -- Temporal dimension
    timestamp DateTime CODEC(DoubleDelta, LZ4),
    
    -- Source information
    src_ip IPv4 CODEC(LZ4),
    src_port UInt16 CODEC(LZ4),
    src_geo_latitude Float32 CODEC(Gorilla, LZ4),
    src_geo_longitude Float32 CODEC(Gorilla, LZ4),
    
    -- Destination information
    dst_ip IPv4 CODEC(LZ4),
    dst_port UInt16 CODEC(LZ4),
    dst_geo_latitude Float32 CODEC(Gorilla, LZ4),
    dst_geo_longitude Float32 CODEC(Gorilla, LZ4),
    
    -- Protocol and flow characteristics
    protocol UInt8 CODEC(LZ4),
    tcp_flags UInt8 CODEC(LZ4),
    
    -- Traffic metrics
    bytes UInt64 CODEC(LZ4),
    packets UInt32 CODEC(LZ4),
    flow_duration UInt32 CODEC(LZ4),
    
    -- Derived fields for analytics (materialized)
    flow_start DateTime MATERIALIZED toDateTime(toUnixTimestamp(timestamp) - flow_duration),
    protocol_name LowCardinality(String) MATERIALIZED CASE protocol
        WHEN 1 THEN 'ICMP'
        WHEN 6 THEN 'TCP'
        WHEN 17 THEN 'UDP'
        ELSE 'Other'
    END
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/flows_replicated', '{replica}')
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (toStartOfHour(timestamp), protocol, src_ip, dst_ip)
SETTINGS 
    index_granularity = 8192,
    -- Enable compression for better storage efficiency
    compress_marks = 1,
    compress_primary_key = 1;

-- Create indexes for high-cardinality IP lookups
-- Note: Indexes are automatically replicated with the table
ALTER TABLE netflow.flows_replicated ON CLUSTER netflow_cluster
ADD INDEX IF NOT EXISTS idx_src_ip src_ip TYPE bloom_filter GRANULARITY 4;

ALTER TABLE netflow.flows_replicated ON CLUSTER netflow_cluster
ADD INDEX IF NOT EXISTS idx_dst_ip dst_ip TYPE bloom_filter GRANULARITY 4;

-- MinMax index for geographic queries (bounding box searches)
ALTER TABLE netflow.flows_replicated ON CLUSTER netflow_cluster
ADD INDEX IF NOT EXISTS idx_src_geo (src_geo_latitude, src_geo_longitude) TYPE minmax GRANULARITY 8;

ALTER TABLE netflow.flows_replicated ON CLUSTER netflow_cluster
ADD INDEX IF NOT EXISTS idx_dst_geo (dst_geo_latitude, dst_geo_longitude) TYPE minmax GRANULARITY 8;

-- Verification queries:
-- 1. Check table exists on all nodes:
--    SELECT hostname(), database, name, engine FROM system.tables WHERE name = 'flows_replicated';
-- 2. Check replication status:
--    SELECT * FROM system.replicas WHERE table = 'flows_replicated';
-- 3. Check ZooKeeper path:
--    SELECT * FROM system.zookeeper WHERE path = '/clickhouse/tables/01/flows_replicated';

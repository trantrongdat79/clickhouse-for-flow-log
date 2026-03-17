-- filepath: sql/schema/01-flows-local.sql
-- Purpose: Create local table for NetFlow data (single-node deployment)
-- Dependencies: ClickHouse running
-- Usage: Execute via clickhouse-client

-- Ensure netflow database exists
CREATE DATABASE IF NOT EXISTS netflow;

-- Drop existing table if running fresh setup
-- DROP TABLE IF EXISTS netflow.flows_local;

CREATE TABLE IF NOT EXISTS netflow.flows_local
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
    
    -- Traffic metrics (use Delta codec for monotonic counters)
    bytes UInt64 CODEC(Delta, LZ4),
    packets UInt32 CODEC(Delta, LZ4),
    flow_duration UInt32 CODEC(Delta, LZ4),
    
    -- Derived fields for analytics (materialized)
    flow_start DateTime MATERIALIZED timestamp - INTERVAL flow_duration SECOND,
    protocol_name String MATERIALIZED CASE protocol
        WHEN 1 THEN 'ICMP'
        WHEN 6 THEN 'TCP'
        WHEN 17 THEN 'UDP'
        ELSE 'Other'
    END
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, cityHash64(src_ip), cityHash64(dst_ip))
SETTINGS 
    index_granularity = 8192,
    -- Enable compression for better storage efficiency
    compress_marks = 1,
    compress_primary_key = 1;

-- Create indexes for high-cardinality IP lookups
-- Bloom filter index for exact IP matches
-- This dramatically speeds up queries like: WHERE src_ip = '192.168.1.1'
ALTER TABLE netflow.flows_local 
ADD INDEX IF NOT EXISTS idx_src_ip src_ip TYPE bloom_filter GRANULARITY 4;

ALTER TABLE netflow.flows_local 
ADD INDEX IF NOT EXISTS idx_dst_ip dst_ip TYPE bloom_filter GRANULARITY 4;

-- MinMax index for geographic queries (bounding box searches)
ALTER TABLE netflow.flows_local 
ADD INDEX IF NOT EXISTS idx_src_geo (src_geo_latitude, src_geo_longitude) TYPE minmax GRANULARITY 8;

ALTER TABLE netflow.flows_local 
ADD INDEX IF NOT EXISTS idx_dst_geo (dst_geo_latitude, dst_geo_longitude) TYPE minmax GRANULARITY 8;

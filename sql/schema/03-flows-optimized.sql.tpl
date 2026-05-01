CREATE DATABASE IF NOT EXISTS netflow;

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

    -- Traffic metrics
    bytes UInt64 CODEC(LZ4),
    packets UInt32 CODEC(LZ4),
    flow_duration UInt32 CODEC(LZ4),

    -- Derived fields for analytics (materialized)
    flow_start DateTime MATERIALIZED toDateTime(toUnixTimestamp(timestamp) - flow_duration),
    protocol_name LowCardinality(String) MATERIALIZED
        CASE protocol
            WHEN 1 THEN 'ICMP'
            WHEN 6 THEN 'TCP'
            WHEN 17 THEN 'UDP'
            ELSE 'Other'
        END
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, protocol, src_ip, dst_ip)
SETTINGS
    index_granularity = 8192,
    compress_marks = 1,
    compress_primary_key = 1;

-- Data-skipping indexes for IP and geo predicates.
ALTER TABLE netflow.flows_local
    ADD INDEX IF NOT EXISTS idx_src_ip src_ip TYPE bloom_filter GRANULARITY 4;

ALTER TABLE netflow.flows_local
    ADD INDEX IF NOT EXISTS idx_dst_ip dst_ip TYPE bloom_filter GRANULARITY 4;

ALTER TABLE netflow.flows_local
    ADD INDEX IF NOT EXISTS idx_src_geo (src_geo_latitude, src_geo_longitude) TYPE minmax GRANULARITY 8;

ALTER TABLE netflow.flows_local
    ADD INDEX IF NOT EXISTS idx_dst_geo (dst_geo_latitude, dst_geo_longitude) TYPE minmax GRANULARITY 8;

-- Phase 2 projections aligned to benchmark query patterns.
ALTER TABLE netflow.flows_local
    ADD PROJECTION IF NOT EXISTS proj_src_ip_daily
    (
        SELECT
            toDate(timestamp) AS d,
            src_ip,
            sum(bytes) AS sum_bytes,
            sum(packets) AS sum_packets,
            count() AS flow_count
        GROUP BY d, src_ip
    );

ALTER TABLE netflow.flows_local
    ADD PROJECTION IF NOT EXISTS proj_protocol_daily
    (
        SELECT
            toDate(timestamp) AS d,
            protocol_name,
            count() AS flow_count,
            sum(bytes) AS sum_bytes,
            sum(packets) AS sum_packets
        GROUP BY d, protocol_name
    );

ALTER TABLE netflow.flows_local
    ADD PROJECTION IF NOT EXISTS proj_dst_port_daily
    (
        SELECT
            toDate(timestamp) AS d,
            dst_port,
            count() AS connections,
            sum(bytes) AS sum_bytes
        GROUP BY d, dst_port
    );

ALTER TABLE netflow.flows_local
    ADD PROJECTION IF NOT EXISTS proj_conversation_daily
    (
        SELECT
            toDate(timestamp) AS d,
            src_ip,
            dst_ip,
            sum(bytes) AS sum_bytes,
            count() AS flow_count
        GROUP BY d, src_ip, dst_ip
    );

ALTER TABLE netflow.flows_local
    ADD PROJECTION IF NOT EXISTS proj_timeseries_minute
    (
        SELECT
            toStartOfMinute(timestamp) AS minute_bucket,
            sum(bytes) AS sum_bytes,
            count() AS flow_count
        GROUP BY minute_bucket
    );

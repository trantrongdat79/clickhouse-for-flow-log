-- filepath: sql/queries/verify_data.sql
-- Purpose: Comprehensive verification queries for NetFlow data
-- Usage: cat verify_data.sql | docker exec -i clickhouse01 clickhouse-client

-- =============================================================================
-- SECTION 1: Basic Statistics
-- =============================================================================

SELECT '=== BASIC STATISTICS ===' as section;

-- Total row count
SELECT 
    'Total Flows' as metric,
    formatReadableQuantity(count()) as value
FROM netflow.flows_local;

-- Time range coverage
SELECT 
    'Earliest Flow' as metric,
    toString(min(timestamp)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Latest Flow' as metric,
    toString(max(timestamp)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Days Covered' as metric,
    toString(dateDiff('day', min(timestamp), max(timestamp))) as value
FROM netflow.flows_local;

-- =============================================================================
-- SECTION 2: Cardinality Analysis
-- =============================================================================

SELECT '' as section;
SELECT '=== CARDINALITY ANALYSIS ===' as section;

SELECT 
    'Unique Source IPs' as metric,
    formatReadableQuantity(uniq(src_ip)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Unique Destination IPs' as metric,
    formatReadableQuantity(uniq(dst_ip)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Unique Source Ports' as metric,
    formatReadableQuantity(uniq(src_port)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Unique Destination Ports' as metric,
    formatReadableQuantity(uniq(dst_port)) as value
FROM netflow.flows_local;

-- =============================================================================
-- SECTION 3: Protocol Distribution
-- =============================================================================

SELECT '' as section;
SELECT '=== PROTOCOL DISTRIBUTION ===' as section;

SELECT 
    protocol,
    protocol_name,
    formatReadableQuantity(count()) as flows,
    round(count() * 100.0 / (SELECT count() FROM netflow.flows_local), 2) as percentage
FROM netflow.flows_local
GROUP BY protocol, protocol_name
ORDER BY count() DESC;

-- =============================================================================
-- SECTION 4: Top Destination Ports (Services)
-- =============================================================================

SELECT '' as section;
SELECT '=== TOP DESTINATION PORTS ===' as section;

SELECT 
    dst_port,
    CASE dst_port
        WHEN 80 THEN 'HTTP'
        WHEN 443 THEN 'HTTPS'
        WHEN 22 THEN 'SSH'
        WHEN 53 THEN 'DNS'
        WHEN 3306 THEN 'MySQL'
        WHEN 5432 THEN 'PostgreSQL'
        WHEN 6379 THEN 'Redis'
        WHEN 8080 THEN 'HTTP-Alt'
        WHEN 27017 THEN 'MongoDB'
        ELSE 'Other'
    END as service,
    formatReadableQuantity(count()) as flows,
    round(count() * 100.0 / (SELECT count() FROM netflow.flows_local), 2) as percentage
FROM netflow.flows_local
GROUP BY dst_port
ORDER BY count() DESC
LIMIT 10;

-- =============================================================================
-- SECTION 5: Top Talkers (by bytes sent)
-- =============================================================================

SELECT '' as section;
SELECT '=== TOP TALKERS (BY BYTES) ===' as section;

SELECT 
    IPv4NumToString(src_ip) as source_ip,
    formatReadableSize(sum(bytes)) as total_bytes,
    formatReadableQuantity(count()) as flow_count,
    round(avg(src_geo_latitude), 2) as latitude,
    round(avg(src_geo_longitude), 2) as longitude
FROM netflow.flows_local
GROUP BY src_ip
ORDER BY sum(bytes) DESC
LIMIT 10;

-- =============================================================================
-- SECTION 6: Top Destinations (by bytes received)
-- =============================================================================

SELECT '' as section;
SELECT '=== TOP DESTINATIONS (BY BYTES) ===' as section;

SELECT 
    IPv4NumToString(dst_ip) as destination_ip,
    formatReadableSize(sum(bytes)) as total_bytes,
    formatReadableQuantity(count()) as flow_count,
    round(avg(dst_geo_latitude), 2) as latitude,
    round(avg(dst_geo_longitude), 2) as longitude
FROM netflow.flows_local
GROUP BY dst_ip
ORDER BY sum(bytes) DESC
LIMIT 10;

-- =============================================================================
-- SECTION 7: Traffic by Hour of Day
-- =============================================================================

SELECT '' as section;
SELECT '=== TRAFFIC BY HOUR OF DAY ===' as section;

SELECT 
    toHour(timestamp) as hour,
    formatReadableQuantity(count()) as flows,
    formatReadableSize(sum(bytes)) as total_bytes
FROM netflow.flows_local
GROUP BY hour
ORDER BY hour;

-- =============================================================================
-- SECTION 8: Geographic Distribution (Source)
-- =============================================================================

SELECT '' as section;
SELECT '=== TOP SOURCE LOCATIONS ===' as section;

SELECT 
    round(src_geo_latitude, 1) as lat,
    round(src_geo_longitude, 1) as lon,
    formatReadableQuantity(count()) as flows,
    formatReadableSize(sum(bytes)) as total_bytes
FROM netflow.flows_local
GROUP BY lat, lon
ORDER BY count() DESC
LIMIT 10;

-- =============================================================================
-- SECTION 9: Traffic Metrics Summary
-- =============================================================================

SELECT '' as section;
SELECT '=== TRAFFIC METRICS SUMMARY ===' as section;

SELECT 
    'Total Bytes' as metric,
    formatReadableSize(sum(bytes)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Average Bytes per Flow' as metric,
    formatReadableSize(avg(bytes)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Total Packets' as metric,
    formatReadableQuantity(sum(packets)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Average Packets per Flow' as metric,
    toString(round(avg(packets), 2)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Average Flow Duration' as metric,
    toString(round(avg(flow_duration), 2)) || ' seconds' as value
FROM netflow.flows_local;

-- =============================================================================
-- SECTION 10: Storage Statistics
-- =============================================================================

SELECT '' as section;
SELECT '=== STORAGE STATISTICS ===' as section;

SELECT 
    'Disk Size (Compressed)' as metric,
    formatReadableSize(sum(bytes_on_disk)) as value
FROM system.parts
WHERE active AND database = 'default' AND table = 'flows_local'
UNION ALL
SELECT 
    'Data Size (Uncompressed)' as metric,
    formatReadableSize(sum(data_uncompressed_bytes)) as value
FROM system.parts
WHERE active AND database = 'default' AND table = 'flows_local'
UNION ALL
SELECT 
    'Compression Ratio' as metric,
    toString(round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2)) || 'x' as value
FROM system.parts
WHERE active AND database = 'default' AND table = 'flows_local'
UNION ALL
SELECT 
    'Number of Parts' as metric,
    toString(count()) as value
FROM system.parts
WHERE active AND database = 'default' AND table = 'flows_local'
UNION ALL
SELECT 
    'Number of Partitions' as metric,
    toString(uniq(partition)) as value
FROM system.parts
WHERE active AND database = 'default' AND table = 'flows_local';

-- =============================================================================
-- SECTION 11: Data Quality Checks
-- =============================================================================

SELECT '' as section;
SELECT '=== DATA QUALITY CHECKS ===' as section;

-- Check for NULL values
SELECT 
    'Rows with NULL timestamps' as check_name,
    toString(countIf(timestamp IS NULL)) as result
FROM netflow.flows_local
UNION ALL
SELECT 
    'Rows with NULL src_ip' as check_name,
    toString(countIf(src_ip IS NULL)) as result
FROM netflow.flows_local
UNION ALL
SELECT 
    'Rows with NULL dst_ip' as check_name,
    toString(countIf(dst_ip IS NULL)) as result
FROM netflow.flows_local
UNION ALL
SELECT 
    'Rows with zero bytes' as check_name,
    toString(countIf(bytes = 0)) as result
FROM netflow.flows_local
UNION ALL
SELECT 
    'Rows with zero packets' as check_name,
    toString(countIf(packets = 0)) as result
FROM netflow.flows_local;

-- Geo-location bounds check
SELECT '' as section;
SELECT 'Geographic Bounds:' as check_name;

SELECT 
    'Latitude Range (Source)' as metric,
    toString(round(min(src_geo_latitude), 2)) || ' to ' || toString(round(max(src_geo_latitude), 2)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Longitude Range (Source)' as metric,
    toString(round(min(src_geo_longitude), 2)) || ' to ' || toString(round(max(src_geo_longitude), 2)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Latitude Range (Destination)' as metric,
    toString(round(min(dst_geo_latitude), 2)) || ' to ' || toString(round(max(dst_geo_latitude), 2)) as value
FROM netflow.flows_local
UNION ALL
SELECT 
    'Longitude Range (Destination)' as metric,
    toString(round(min(dst_geo_longitude), 2)) || ' to ' || toString(round(max(dst_geo_longitude), 2)) as value
FROM netflow.flows_local;

SELECT '' as section;
SELECT '=== VERIFICATION COMPLETE ===' as section;

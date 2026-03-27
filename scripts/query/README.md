# NetFlow Query Benchmarking Guide

## Overview

This guide documents the separated query approach for NetFlow data analysis using ClickHouse and InfluxDB. Each complex query has been broken down into individual component queries for better understanding and benchmarking.

## Query Structure

All queries are separated into individual components:
- **Q1**: Top Talkers (3 sub-queries)
- **Q2**: Traffic Time-Series (2 sub-queries)
- **Q3**: Protocol Distribution (3 sub-queries)
- **Q4**: Top Destination Ports (2 sub-queries)
- **Q5**: Bandwidth Percentiles (3 sub-queries)
- **Q6**: Top Conversations (2 sub-queries)

---

## I. ClickHouse Separated Queries

### Q1: Top Talkers by Source IP

**Q1.a: Total bytes by src_ip**
```sql
SELECT 
    src_ip,
    SUM(bytes) as total_bytes
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY src_ip
ORDER BY total_bytes DESC
LIMIT 10;
```

**Q1.b: Total packets by src_ip**
```sql
SELECT 
    src_ip,
    SUM(packets) as total_packets
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY src_ip
ORDER BY total_packets DESC
LIMIT 10;
```

**Q1.c: Flow count by src_ip**
```sql
SELECT 
    src_ip,
    COUNT(*) as flow_count
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY src_ip
ORDER BY flow_count DESC
LIMIT 10;
```

### Q2: Traffic Time-Series (1-minute buckets)

**Q2.a: Bytes aggregated by time bucket**
```sql
SELECT 
    toStartOfMinute(timestamp) as time_bucket,
    SUM(bytes) as total_bytes
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY time_bucket
ORDER BY time_bucket
LIMIT 100;
```

**Q2.b: Flow count by time bucket**
```sql
SELECT 
    toStartOfMinute(timestamp) as time_bucket,
    COUNT(*) as flow_count
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY time_bucket
ORDER BY time_bucket
LIMIT 100;
```

### Q3: Protocol Distribution

**Q3.a: Flow count by protocol**
```sql
SELECT 
    protocol_name,
    COUNT(*) as flow_count
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY protocol_name;
```

**Q3.b: Total bytes by protocol**
```sql
SELECT 
    protocol_name,
    SUM(bytes) as total_bytes
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY protocol_name;
```

**Q3.c: Total packets by protocol**
```sql
SELECT 
    protocol_name,
    SUM(packets) as total_packets
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY protocol_name;
```

### Q4: Top Destination Ports

**Q4.a: Connection count by dst_port**
```sql
SELECT 
    dst_port,
    COUNT(*) as connections
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
AND dst_port > 0
GROUP BY dst_port
ORDER BY connections DESC
LIMIT 20;
```

**Q4.b: Total bytes by dst_port**
```sql
SELECT 
    dst_port,
    SUM(bytes) as total_bytes
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
AND dst_port > 0
GROUP BY dst_port
ORDER BY total_bytes DESC
LIMIT 20;
```

### Q5: Bandwidth Percentiles (by hour)

**Q5.a: P50 percentile by hour**
```sql
SELECT 
    toStartOfHour(timestamp) as hour,
    quantile(0.50)(bytes) as p50
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY hour
ORDER BY hour
LIMIT 100;
```

**Q5.b: P95 percentile by hour**
```sql
SELECT 
    toStartOfHour(timestamp) as hour,
    quantile(0.95)(bytes) as p95
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY hour
ORDER BY hour
LIMIT 100;
```

**Q5.c: P99 percentile by hour**
```sql
SELECT 
    toStartOfHour(timestamp) as hour,
    quantile(0.99)(bytes) as p99
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY hour
ORDER BY hour
LIMIT 100;
```

### Q6: Top Conversations (IP pairs)

**Q6.a: Total bytes by conversation**
```sql
SELECT 
    src_ip,
    dst_ip,
    SUM(bytes) as total_bytes
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY src_ip, dst_ip
ORDER BY total_bytes DESC
LIMIT 10;
```

**Q6.b: Flow count by conversation**
```sql
SELECT 
    src_ip,
    dst_ip,
    COUNT(*) as flow_count
FROM netflow.flows_local
WHERE timestamp BETWEEN '2026-03-01 00:00:00' AND '2026-03-07 23:59:59'
GROUP BY src_ip, dst_ip
ORDER BY flow_count DESC
LIMIT 10;
```

---

## II. InfluxDB Separated Queries (Flux)

### Q1: Top Talkers by Source IP

**Q1.a: Total bytes by src_ip**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip"])
    |> sum()
    |> rename(columns: {_value: "total_bytes"})
    |> sort(columns: ["total_bytes"], desc: true)
    |> limit(n: 10)
```

**Q1.b: Total packets by src_ip**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "packets")
    |> group(columns: ["src_ip"])
    |> sum()
    |> rename(columns: {_value: "total_packets"})
    |> sort(columns: ["total_packets"], desc: true)
    |> limit(n: 10)
```

**Q1.c: Flow count by src_ip**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip"])
    |> count()
    |> rename(columns: {_value: "flow_count"})
    |> sort(columns: ["flow_count"], desc: true)
    |> limit(n: 10)
```

### Q2: Traffic Time-Series (1-minute buckets)

**Q2.a: Bytes aggregated by time bucket**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> aggregateWindow(every: 1m, fn: sum, createEmpty: false)
    |> rename(columns: {_value: "total_bytes"})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
```

**Q2.b: Flow count by time bucket**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> aggregateWindow(every: 1m, fn: count, createEmpty: false)
    |> rename(columns: {_value: "flow_count"})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
```

### Q3: Protocol Distribution

**Q3.a: Flow count by protocol**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["protocol_name"])
    |> count()
    |> rename(columns: {_value: "flow_count"})
```

**Q3.b: Total bytes by protocol**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["protocol_name"])
    |> sum()
    |> rename(columns: {_value: "total_bytes"})
```

**Q3.c: Total packets by protocol**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "packets")
    |> group(columns: ["protocol_name"])
    |> sum()
    |> rename(columns: {_value: "total_packets"})
```

### Q4: Top Destination Ports

**Q4.a: Connection count by dst_port**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> filter(fn: (r) => int(v: r.dst_port) > 0)
    |> group(columns: ["dst_port"])
    |> count()
    |> rename(columns: {_value: "connections"})
    |> sort(columns: ["connections"], desc: true)
    |> limit(n: 20)
```

**Q4.b: Total bytes by dst_port**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> filter(fn: (r) => int(v: r.dst_port) > 0)
    |> group(columns: ["dst_port"])
    |> sum()
    |> rename(columns: {_value: "total_bytes"})
    |> sort(columns: ["total_bytes"], desc: true)
    |> limit(n: 20)
```

### Q5: Bandwidth Percentiles (by hour)

**Q5.a: P50 percentile by hour**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> aggregateWindow(every: 1h, fn: (tables=<-, column) =>
        tables |> quantile(q: 0.50, method: "estimate_tdigest"),
        createEmpty: false
    )
    |> rename(columns: {_value: "p50"})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
```

**Q5.b: P95 percentile by hour**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> aggregateWindow(every: 1h, fn: (tables=<-, column) =>
        tables |> quantile(q: 0.95, method: "estimate_tdigest"),
        createEmpty: false
    )
    |> rename(columns: {_value: "p95"})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
```

**Q5.c: P99 percentile by hour**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> aggregateWindow(every: 1h, fn: (tables=<-, column) =>
        tables |> quantile(q: 0.99, method: "estimate_tdigest"),
        createEmpty: false
    )
    |> rename(columns: {_value: "p99"})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
```

### Q6: Top Conversations (IP pairs)

**Q6.a: Total bytes by conversation**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip", "dst_ip"])
    |> sum()
    |> rename(columns: {_value: "total_bytes"})
    |> sort(columns: ["total_bytes"], desc: true)
    |> limit(n: 10)
```

**Q6.b: Flow count by conversation**
```flux
from(bucket: "flows")
    |> range(start: 2026-03-01T00:00:00Z, stop: 2026-03-07T23:59:59Z)
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip", "dst_ip"])
    |> count()
    |> rename(columns: {_value: "flow_count"})
    |> sort(columns: ["flow_count"], desc: true)
    |> limit(n: 10)
```

---

## III. Running the Benchmarks

### ClickHouse Separated Queries
```bash
cd /path/to/scripts/query
python3 query_clickhouse_separated.py
```

Output file: `benchmark-results/query/query-clickhouse-separated-output.txt`

### InfluxDB Separated Queries
```bash
cd /path/to/scripts/query
python3 query_influxdb_separated.py
```

Output file: `benchmark-results/query/query-influxdb-separated-output.txt`

---

## IV. Performance Timing

Both scripts measure query execution time using Python's `time.perf_counter()`:

**ClickHouse Example:**
```python
def run_query(name, query):
    start = time.perf_counter()
    result = client.query(query)
    elapsed_ms = (time.perf_counter() - start) * 1000
    return result, elapsed_ms
```

**InfluxDB Example:**
```python
def run_query(name, flux_query):
    start = time.perf_counter()
    result = query_api.query(flux_query)
    elapsed_ms = (time.perf_counter() - start) * 1000
    return records, elapsed_ms
```

---

## V. Query Comparison Results

Based on test execution (March 2026 dataset):

### ClickHouse Performance
- **Q1 queries**: ~14-16 ms each
- **Q2 queries**: ~11-13 ms each
- **Q3 queries**: ~11-12 ms each
- **Q4 queries**: ~33-49 ms each
- **Q5 queries**: ~12-14 ms each
- **Q6 queries**: ~11 ms each

### InfluxDB Performance
- **Q1 queries**: ~18-21 ms each
- **Q2 queries**: ~108-119 ms each
- **Q3 queries**: ~15-22 ms each
- **Q4 queries**: ~63-65 ms each
- **Q5 queries**: ~149-152 ms each
- **Q6 queries**: ~26-33 ms each

### Data Verification
All queries produce equivalent results between ClickHouse and InfluxDB:
- **Q1**: Same top 10 IPs with identical byte/packet/flow counts
- **Q2**: Matching time-series aggregations
- **Q3**: Identical protocol distributions (ICMP: 29 flows, TCP: 402 flows, UDP: 149 flows)
- **Q4**: Same top ports by connections and bytes
- **Q5**: Consistent percentile calculations per hour
- **Q6**: Matching conversation pairs with identical traffic volumes

---

## VI. Notes

1. **Query Separation Benefits:**
   - Easier to understand individual metrics
   - Better for targeted analysis
   - Simpler debugging and optimization
   - Can mix and match queries as needed

2. **Time Range:**
   - Default: 2026-03-01 to 2026-03-07
   - Configurable in script variables

3. **Data Consistency:**
   - Both databases query the same source data
   - Results are numerically identical
   - Only output format differs (tabular vs FluxRecord objects)

Data has been updated
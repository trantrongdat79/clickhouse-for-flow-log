#!/usr/bin/env python3
from influxdb_client import InfluxDBClient
import time
import subprocess
import json
from pathlib import Path

# Configuration
URL = 'http://localhost:8086'
USERNAME = 'admin'
PASSWORD = 'admin_password_change_me'
ORG = 'netflow'
BUCKET = 'flows'
TIME_START = '2026-03-01T00:00:00Z'
TIME_END = '2026-03-07T23:59:59Z'

OUTPUT_DIR = Path(__file__).parent.parent.parent / 'benchmark-results' / 'query'
OUTPUT_FILE = OUTPUT_DIR / 'query-influxdb-output.txt'

# Get token from InfluxDB CLI
def get_influx_token():
    try:
        result = subprocess.run(
            ['docker', 'exec', 'influxdb', 'influx', 'auth', 'list', '--json'],
            capture_output=True, text=True, check=True
        )
        auths = json.loads(result.stdout)
        if auths and len(auths) > 0:
            return auths[0]['token']
    except:
        pass
    return None

TOKEN = get_influx_token()
if not TOKEN:
    print("Error: Could not retrieve InfluxDB token")
    exit(1)

client = InfluxDBClient(url=URL, token=TOKEN, org=ORG, timeout=60000)
query_api = client.query_api()

def run_query(name, flux_query):
    """Execute Flux query and measure time"""
    try:
        start = time.perf_counter()
        result = query_api.query(flux_query)
        
        elapsed_ms = (time.perf_counter() - start) * 1000

        # Materialize results
        records = []
        for table in result:
            for record in table.records:
                records.append(record)
        
        return records, elapsed_ms
    except Exception as e:
        elapsed_ms = (time.perf_counter() - start) * 1000
        return None, elapsed_ms, str(e)

def write_output(f, query_name, records, elapsed_ms, error=None):
    """Write query results and timing to file"""
    f.write(f"\n{'='*80}\n")
    f.write(f"Query: {query_name}\n")
    f.write(f"Elapsed Time: {elapsed_ms:.2f} ms\n")
    f.write(f"{'-'*80}\n")
    
    if error:
        f.write(f"ERROR: {error}\n")
        return
    
    # Write records (limit to first 20)
    for i, record in enumerate(records[:20]):
        f.write(f"{record}\n")
    
    if len(records) > 20:
        f.write(f"... ({len(records) - 20} more records)\n")
    
    f.write(f"\nTotal Records: {len(records)}\n")

# Ensure output directory exists
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Open output file
with open(OUTPUT_FILE, 'w') as f:
    f.write("InfluxDB Separated Query Benchmark Results\n")
    f.write(f"Time Range: {TIME_START} to {TIME_END}\n")
    f.write(f"{'='*80}\n")

    # ===== Q1: Top Talkers =====
    
    # Q1.a: Total bytes by src_ip
    q1a = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip"])
    |> sum()
    |> rename(columns: {{_value: "total_bytes"}})
    |> sort(columns: ["total_bytes"], desc: true)
    |> limit(n: 10)
    """
    result = run_query("Q1.a: Total bytes by src_ip", q1a)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q1.a: Total bytes by src_ip", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q1.a: Total bytes by src_ip", records, elapsed)

    # Q1.b: Total packets by src_ip
    q1b = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "packets")
    |> group(columns: ["src_ip"])
    |> sum()
    |> rename(columns: {{_value: "total_packets"}})
    |> sort(columns: ["total_packets"], desc: true)
    |> limit(n: 10)
    """
    result = run_query("Q1.b: Total packets by src_ip", q1b)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q1.b: Total packets by src_ip", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q1.b: Total packets by src_ip", records, elapsed)

    # Q1.c: Flow count by src_ip
    q1c = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip"])
    |> count()
    |> rename(columns: {{_value: "flow_count"}})
    |> sort(columns: ["flow_count"], desc: true)
    |> limit(n: 10)
    """
    result = run_query("Q1.c: Flow count by src_ip", q1c)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q1.c: Flow count by src_ip", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q1.c: Flow count by src_ip", records, elapsed)

    # ===== Q2: Traffic Time-Series =====
    
    # Q2.a: Bytes aggregated by time bucket (1-minute)
    q2a = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group()
    |> aggregateWindow(every: 1m, fn: sum, createEmpty: false)
    |> rename(columns: {{_value: "total_bytes"}})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
    """
    result = run_query("Q2.a: Bytes by time bucket (1-min)", q2a)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q2.a: Bytes by time bucket (1-min)", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q2.a: Bytes by time bucket (1-min)", records, elapsed)

    # Q2.b: Flow count by time bucket (1-minute)
    q2b = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group()
    |> aggregateWindow(every: 1m, fn: count, createEmpty: false)
    |> rename(columns: {{_value: "flow_count"}})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
    """
    result = run_query("Q2.b: Flow count by time bucket (1-min)", q2b)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q2.b: Flow count by time bucket (1-min)", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q2.b: Flow count by time bucket (1-min)", records, elapsed)

    # ===== Q3: Protocol Distribution =====
    
    # Q3.a: Flow count by protocol
    q3a = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["protocol_name"])
    |> count()
    |> rename(columns: {{_value: "flow_count"}})
    """
    result = run_query("Q3.a: Flow count by protocol", q3a)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q3.a: Flow count by protocol", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q3.a: Flow count by protocol", records, elapsed)

    # Q3.b: Total bytes by protocol
    q3b = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["protocol_name"])
    |> sum()
    |> rename(columns: {{_value: "total_bytes"}})
    """
    result = run_query("Q3.b: Total bytes by protocol", q3b)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q3.b: Total bytes by protocol", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q3.b: Total bytes by protocol", records, elapsed)

    # Q3.c: Total packets by protocol
    q3c = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "packets")
    |> group(columns: ["protocol_name"])
    |> sum()
    |> rename(columns: {{_value: "total_packets"}})
    """
    result = run_query("Q3.c: Total packets by protocol", q3c)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q3.c: Total packets by protocol", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q3.c: Total packets by protocol", records, elapsed)

    # ===== Q4: Top Destination Ports =====
    
    # Q4.a: Connection count by dst_port
    q4a = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> filter(fn: (r) => int(v: r.dst_port) > 0)
    |> group(columns: ["dst_port"])
    |> count()
    |> rename(columns: {{_value: "connections"}})
    |> group()
    |> sort(columns: ["connections"], desc: true)
    |> limit(n: 20)
    """
    result = run_query("Q4.a: Connection count by dst_port", q4a)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q4.a: Connection count by dst_port", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q4.a: Connection count by dst_port", records, elapsed)

    # Q4.b: Total bytes by dst_port
    q4b = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> filter(fn: (r) => int(v: r.dst_port) > 0)
    |> group(columns: ["dst_port"])
    |> sum()
    |> rename(columns: {{_value: "total_bytes"}})
    |> group()
    |> sort(columns: ["total_bytes"], desc: true)
    |> limit(n: 20)
    """
    result = run_query("Q4.b: Total bytes by dst_port", q4b)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q4.b: Total bytes by dst_port", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q4.b: Total bytes by dst_port", records, elapsed)

    # ===== Q5: Bandwidth Percentiles =====
    
    # Q5.a: P50 percentile by hour
    q5a = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group()
    |> aggregateWindow(every: 1h, fn: (tables=<-, column) =>
        tables |> quantile(q: 0.50, method: "exact_selector"),
        createEmpty: false
    )
    |> rename(columns: {{_value: "p50"}})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
    """
    result = run_query("Q5.a: P50 percentile by hour", q5a)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q5.a: P50 percentile by hour", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q5.a: P50 percentile by hour", records, elapsed)

    # Q5.b: P95 percentile by hour
    q5b = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group()
    |> aggregateWindow(every: 1h, fn: (tables=<-, column) =>
        tables |> quantile(q: 0.95, method: "exact_selector"),
        createEmpty: false
    )
    |> rename(columns: {{_value: "p95"}})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
    """
    result = run_query("Q5.b: P95 percentile by hour", q5b)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q5.b: P95 percentile by hour", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q5.b: P95 percentile by hour", records, elapsed)

    # Q5.c: P99 percentile by hour
    q5c = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group()
    |> aggregateWindow(every: 1h, fn: (tables=<-, column) =>
        tables |> quantile(q: 0.99, method: "exact_selector"),
        createEmpty: false
    )
    |> rename(columns: {{_value: "p99"}})
    |> sort(columns: ["_time"], desc: false)
    |> limit(n: 100)
    """
    result = run_query("Q5.c: P99 percentile by hour", q5c)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q5.c: P99 percentile by hour", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q5.c: P99 percentile by hour", records, elapsed)

    # ===== Q6: Top Conversations =====
    
    # Q6.a: Total bytes by conversation (src_ip, dst_ip)
    q6a = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip", "dst_ip"])
    |> sum()
    |> rename(columns: {{_value: "total_bytes"}})
    |> group()
    |> sort(columns: ["total_bytes"], desc: true)
    |> limit(n: 10)
    """
    result = run_query("Q6.a: Total bytes by conversation", q6a)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q6.a: Total bytes by conversation", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q6.a: Total bytes by conversation", records, elapsed)

    # Q6.b: Flow count by conversation (src_ip, dst_ip)
    q6b = f"""
from(bucket: "{BUCKET}")
    |> range(start: {TIME_START}, stop: {TIME_END})
    |> filter(fn: (r) => r._measurement == "flows")
    |> filter(fn: (r) => r._field == "bytes")
    |> group(columns: ["src_ip", "dst_ip"])
    |> count()
    |> rename(columns: {{_value: "flow_count"}})
    |> group()
    |> sort(columns: ["flow_count"], desc: true)
    |> limit(n: 10)
    """
    result = run_query("Q6.b: Flow count by conversation", q6b)
    if len(result) == 3:
        records, elapsed, error = result
        write_output(f, "Q6.b: Flow count by conversation", records, elapsed, error)
    else:
        records, elapsed = result
        write_output(f, "Q6.b: Flow count by conversation", records, elapsed)

client.close()
print(f"Results written to: {OUTPUT_FILE}")

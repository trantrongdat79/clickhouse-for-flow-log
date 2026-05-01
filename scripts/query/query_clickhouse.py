#!/usr/bin/env python3
import clickhouse_connect
import time
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
HOST = 'localhost'
PORT = 8123
USERNAME = 'default'
PASSWORD = 'admin'
DATABASE = 'netflow'
TABLE = 'flows_local'
now = datetime.utcnow()
TIME_START = (now - timedelta(days=7)).strftime('%Y-%m-%d %H:%M:%S')
TIME_END = now.strftime('%Y-%m-%d %H:%M:%S')

OUTPUT_DIR = Path(__file__).parent.parent.parent / 'benchmark-results' / 'query'
OUTPUT_FILE = OUTPUT_DIR / 'query-clickhouse-output.txt'

client = clickhouse_connect.get_client(host=HOST, port=PORT, username=USERNAME, password=PASSWORD)

def run_query(name, query):
    """Execute query and measure time"""
    start = time.perf_counter()
    result = client.query(query)
    elapsed_ms = (time.perf_counter() - start) * 1000
    return result, elapsed_ms

def write_output(f, query_name, result, elapsed_ms):
    """Write query results and timing to file"""
    f.write(f"\n{'='*80}\n")
    f.write(f"Query: {query_name}\n")
    f.write(f"Elapsed Time: {elapsed_ms:.2f} ms\n")
    f.write(f"{'-'*80}\n")
    
    # Write column names
    if result.column_names:
        f.write('\t'.join(result.column_names) + '\n')
    
    # Write rows (limit to first 20)
    for row in result.result_rows[:20]:
        f.write('\t'.join(str(val) for val in row) + '\n')
    
    if len(result.result_rows) > 20:
        f.write(f"... ({len(result.result_rows) - 20} more rows)\n")
    
    f.write(f"\nTotal Rows: {len(result.result_rows)}\n")

# Ensure output directory exists
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Open output file
with open(OUTPUT_FILE, 'w') as f:
    f.write("ClickHouse Separated Query Benchmark Results\n")
    f.write(f"Time Range: {TIME_START} to {TIME_END}\n")
    f.write(f"{'='*80}\n")

    # ===== Q1: Top Talkers =====
    
    # Q1.a: Total bytes by src_ip
    q1a = f"""
    SELECT 
        src_ip,
        SUM(bytes) as total_bytes
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY src_ip
    ORDER BY total_bytes DESC
    LIMIT 10
    """
    result, elapsed = run_query("Q1.a: Total bytes by src_ip", q1a)
    write_output(f, "Q1.a: Total bytes by src_ip", result, elapsed)

    # Q1.b: Total packets by src_ip
    q1b = f"""
    SELECT 
        src_ip,
        SUM(packets) as total_packets
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY src_ip
    ORDER BY total_packets DESC
    LIMIT 10
    """
    result, elapsed = run_query("Q1.b: Total packets by src_ip", q1b)
    write_output(f, "Q1.b: Total packets by src_ip", result, elapsed)

    # Q1.c: Flow count by src_ip
    q1c = f"""
    SELECT 
        src_ip,
        COUNT(*) as flow_count
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY src_ip
    ORDER BY flow_count DESC
    LIMIT 10
    """
    result, elapsed = run_query("Q1.c: Flow count by src_ip", q1c)
    write_output(f, "Q1.c: Flow count by src_ip", result, elapsed)

    # ===== Q2: Traffic Time-Series =====
    
    # Q2.a: Bytes aggregated by time bucket (1-minute)
    q2a = f"""
    SELECT 
        toStartOfMinute(timestamp) as time_bucket,
        SUM(bytes) as total_bytes
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY time_bucket
    ORDER BY time_bucket
    LIMIT 100
    """
    result, elapsed = run_query("Q2.a: Bytes by time bucket (1-min)", q2a)
    write_output(f, "Q2.a: Bytes by time bucket (1-min)", result, elapsed)

    # Q2.b: Flow count by time bucket (1-minute)
    q2b = f"""
    SELECT 
        toStartOfMinute(timestamp) as time_bucket,
        COUNT(*) as flow_count
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY time_bucket
    ORDER BY time_bucket
    LIMIT 100
    """
    result, elapsed = run_query("Q2.b: Flow count by time bucket (1-min)", q2b)
    write_output(f, "Q2.b: Flow count by time bucket (1-min)", result, elapsed)

    # ===== Q3: Protocol Distribution =====
    
    # Q3.a: Flow count by protocol
    q3a = f"""
    SELECT 
        protocol_name,
        COUNT(*) as flow_count
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY protocol_name
    """
    result, elapsed = run_query("Q3.a: Flow count by protocol", q3a)
    write_output(f, "Q3.a: Flow count by protocol", result, elapsed)

    # Q3.b: Total bytes by protocol
    q3b = f"""
    SELECT 
        protocol_name,
        SUM(bytes) as total_bytes
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY protocol_name
    """
    result, elapsed = run_query("Q3.b: Total bytes by protocol", q3b)
    write_output(f, "Q3.b: Total bytes by protocol", result, elapsed)

    # Q3.c: Total packets by protocol
    q3c = f"""
    SELECT 
        protocol_name,
        SUM(packets) as total_packets
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY protocol_name
    """
    result, elapsed = run_query("Q3.c: Total packets by protocol", q3c)
    write_output(f, "Q3.c: Total packets by protocol", result, elapsed)

    # ===== Q4: Top Destination Ports =====
    
    # Q4.a: Connection count by dst_port
    q4a = f"""
    SELECT 
        dst_port,
        COUNT(*) as connections
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    AND dst_port > 0
    GROUP BY dst_port
    ORDER BY connections DESC
    LIMIT 20
    """
    result, elapsed = run_query("Q4.a: Connection count by dst_port", q4a)
    write_output(f, "Q4.a: Connection count by dst_port", result, elapsed)

    # Q4.b: Total bytes by dst_port
    q4b = f"""
    SELECT 
        dst_port,
        SUM(bytes) as total_bytes
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    AND dst_port > 0
    GROUP BY dst_port
    ORDER BY total_bytes DESC
    LIMIT 20
    """
    result, elapsed = run_query("Q4.b: Total bytes by dst_port", q4b)
    write_output(f, "Q4.b: Total bytes by dst_port", result, elapsed)

    # ===== Q5: Bandwidth Percentiles =====
    
    # Q5.a: P50 percentile by hour
    q5a = f"""
    SELECT 
        toStartOfHour(timestamp) as hour,
        quantile(0.50)(bytes) as p50
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY hour
    ORDER BY hour
    LIMIT 100
    """
    result, elapsed = run_query("Q5.a: P50 percentile by hour", q5a)
    write_output(f, "Q5.a: P50 percentile by hour", result, elapsed)

    # Q5.b: P95 percentile by hour
    q5b = f"""
    SELECT 
        toStartOfHour(timestamp) as hour,
        quantile(0.95)(bytes) as p95
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY hour
    ORDER BY hour
    LIMIT 100
    """
    result, elapsed = run_query("Q5.b: P95 percentile by hour", q5b)
    write_output(f, "Q5.b: P95 percentile by hour", result, elapsed)

    # Q5.c: P99 percentile by hour
    q5c = f"""
    SELECT 
        toStartOfHour(timestamp) as hour,
        quantile(0.99)(bytes) as p99
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY hour
    ORDER BY hour
    LIMIT 100
    """
    result, elapsed = run_query("Q5.c: P99 percentile by hour", q5c)
    write_output(f, "Q5.c: P99 percentile by hour", result, elapsed)

    # ===== Q6: Top Conversations =====
    
    # Q6.a: Total bytes by conversation (src_ip, dst_ip)
    q6a = f"""
    SELECT 
        src_ip,
        dst_ip,
        SUM(bytes) as total_bytes
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY src_ip, dst_ip
    ORDER BY total_bytes DESC
    LIMIT 10
    """
    result, elapsed = run_query("Q6.a: Total bytes by conversation", q6a)
    write_output(f, "Q6.a: Total bytes by conversation", result, elapsed)

    # Q6.b: Flow count by conversation (src_ip, dst_ip)
    q6b = f"""
    SELECT 
        src_ip,
        dst_ip,
        COUNT(*) as flow_count
    FROM {DATABASE}.{TABLE}
    WHERE timestamp BETWEEN '{TIME_START}' AND '{TIME_END}'
    GROUP BY src_ip, dst_ip
    ORDER BY flow_count DESC
    LIMIT 10
    """
    result, elapsed = run_query("Q6.b: Flow count by conversation", q6b)
    write_output(f, "Q6.b: Flow count by conversation", result, elapsed)

print(f"Results written to: {OUTPUT_FILE}")

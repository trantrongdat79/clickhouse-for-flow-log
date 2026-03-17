#!/usr/bin/env python3
"""
Script: ingest_influxdb.py
Purpose: Ingest JSONEachRow flow data into InfluxDB 2.x
Usage: python ingest_influxdb.py [data_directory]
Author: NetFlow Analytics Team
Date: 2026-03-16
"""

import os
import sys
import json
import time
import glob
from datetime import datetime
from pathlib import Path

try:
    from influxdb_client import InfluxDBClient, Point
    from influxdb_client.client.write_api import SYNCHRONOUS, WriteOptions
except ImportError:
    print("ERROR: influxdb-client library not found!")
    print("Install it with: pip install influxdb-client")
    sys.exit(1)

# Configuration from environment variables with defaults
INFLUXDB_URL = os.getenv("INFLUXDB_URL", "http://localhost:8086")
INFLUXDB_TOKEN = os.getenv("INFLUXDB_TOKEN", "my-super-secret-auth-token")
INFLUXDB_ORG = os.getenv("INFLUXDB_ORG", "netflow")
INFLUXDB_BUCKET = os.getenv("INFLUXDB_BUCKET", "flows")

# ANSI color codes
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color


def print_banner():
    """Print the script banner"""
    print("=" * 50)
    print("InfluxDB Data Ingestion")
    print("=" * 50)
    print()
    print("Configuration:")
    print(f"  InfluxDB URL:  {INFLUXDB_URL}")
    print(f"  Organization:  {INFLUXDB_ORG}")
    print(f"  Bucket:        {INFLUXDB_BUCKET}")
    print()


def format_number(n):
    """Format number with thousands separators"""
    return f"{n:,}"


def convert_json_to_point(record):
    """
    Convert a JSON flow record to an InfluxDB Point
    
    InfluxDB data model:
    - Measurement: flows
    - Tags: indexed fields for fast filtering (src_ip, dst_ip, protocol)
    - Fields: actual metric values (bytes, packets, flow_duration, coordinates)
    - Timestamp: time of the flow
    """
    # Parse timestamp from JSON
    ts = datetime.strptime(record['timestamp'], '%Y-%m-%d %H:%M:%S')
    
    # Determine protocol name
    protocol_map = {1: 'ICMP', 6: 'TCP', 17: 'UDP'}
    protocol_num = record['protocol']
    protocol_name = protocol_map.get(protocol_num, 'Other')
    
    # Create Point - measurement name is "flows"
    point = Point("flows") \
        .time(ts) \
        .tag("src_ip", record['src_ip']) \
        .tag("dst_ip", record['dst_ip']) \
        .tag("protocol", str(protocol_num)) \
        .tag("protocol_name", protocol_name) \
        .tag("src_port", str(record['src_port'])) \
        .tag("dst_port", str(record['dst_port'])) \
        .field("bytes", int(record['bytes'])) \
        .field("packets", int(record['packets'])) \
        .field("flow_duration", int(record['flow_duration'])) \
        .field("tcp_flags", int(record['tcp_flags'])) \
        .field("src_geo_latitude", float(record['src_geo_latitude'])) \
        .field("src_geo_longitude", float(record['src_geo_longitude'])) \
        .field("dst_geo_latitude", float(record['dst_geo_latitude'])) \
        .field("dst_geo_longitude", float(record['dst_geo_longitude']))
    
    return point


def get_record_count(client, timeout_seconds=30):
    """Query the total number of records in the bucket"""
    # For large datasets, use a simpler count query with limited time range
    # Counting all records from 0 can be very slow
    query = f'''
    from(bucket: "{INFLUXDB_BUCKET}")
      |> range(start: -30d)
      |> filter(fn: (r) => r._measurement == "flows")
      |> count()
      |> group()
      |> sum()
    '''
    
    try:
        query_api = client.query_api()
        result = query_api.query(query, org=INFLUXDB_ORG)
        
        # Parse result
        total = 0
        for table in result:
            for record in table.records:
                if hasattr(record, '_value'):
                    total += record.get_value()
        
        return total
    except Exception as e:
        print(f"{YELLOW}Warning: Could not query record count (this is normal for large datasets): {e}{NC}")
        return -1  # Return -1 to indicate count unavailable


def ingest_file(client, write_api, filepath, use_async=True):
    """
    Ingest a single JSON file into InfluxDB
    Returns: (records_count, file_size_bytes, elapsed_seconds)
    """
    filename = os.path.basename(filepath)
    filesize = os.path.getsize(filepath)
    filesize_mb = filesize / 1024 / 1024
    
    print(f"{BLUE}Processing:{NC} {filename} ({filesize_mb:.2f} MB)")
    
    start_time = time.time()
    records_count = 0
    batch = []
    # Async mode uses internal batching, so we use smaller batches here
    # Sync mode benefits from larger batches
    batch_size = 1000 if use_async else 5000
    
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                
                try:
                    record = json.loads(line)
                    point = convert_json_to_point(record)
                    batch.append(point)
                    records_count += 1
                    
                    # Write batch when it reaches batch_size
                    if len(batch) >= batch_size:
                        write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=batch)
                        batch = []
                        
                except json.JSONDecodeError as e:
                    print(f"{YELLOW}Warning: Skipping invalid JSON line: {e}{NC}")
                    continue
                except Exception as e:
                    print(f"{YELLOW}Warning: Error processing record: {e}{NC}")
                    continue
        
        # Write remaining records in batch
        if batch:
            write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=batch)
        
        # For async mode, flush to ensure all writes complete
        if use_async:
            write_api.flush()
        
        elapsed = time.time() - start_time
        
        # Calculate throughput
        if elapsed > 0:
            throughput_mb = filesize_mb / elapsed
            throughput_rows = records_count / elapsed
        else:
            throughput_mb = 0
            throughput_rows = 0
        
        print(f"  {GREEN}✓{NC} Complete in {elapsed:.1f}s ({throughput_mb:.2f} MB/s, {throughput_rows:.0f} rows/s)")
        print(f"  Records processed: {format_number(records_count)}")
        
        return records_count, filesize, elapsed
        
    except Exception as e:
        print(f"{RED}ERROR: Failed to ingest file {filename}: {e}{NC}")
        raise


def main():
    """Main ingestion function"""
    # Determine data directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_data_dir = os.path.join(script_dir, "../../data-gen/output")
    data_dir = sys.argv[1] if len(sys.argv) > 1 else default_data_dir
    data_dir = os.path.abspath(data_dir)
    
    print_banner()
    print(f"  Data dir:      {data_dir}")
    print()
    
    # Check if data directory exists
    if not os.path.isdir(data_dir):
        print(f"{RED}ERROR: Data directory not found: {data_dir}{NC}")
        print("Please generate data first: cd ../../data-gen && python generate_flows.py")
        sys.exit(1)
    
    # Find JSON files
    json_files = sorted(glob.glob(os.path.join(data_dir, "flows_*.json")))
    if not json_files:
        print(f"{RED}ERROR: No flows_*.json files found in {data_dir}{NC}")
        sys.exit(1)
    
    print(f"Found {len(json_files)} data file(s) to ingest")
    print()
    
    # Connect to InfluxDB
    print("Connecting to InfluxDB...")
    try:
        client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
        # Test connection
        health = client.health()
        if health.status != "pass":
            print(f"{RED}ERROR: InfluxDB health check failed: {health.message}{NC}")
            sys.exit(1)
        print(f"{GREEN}✓{NC} Connected successfully")
        print()
    except Exception as e:
        print(f"{RED}ERROR: Failed to connect to InfluxDB: {e}{NC}")
        print(f"Make sure InfluxDB is running at {INFLUXDB_URL}")
        sys.exit(1)
    
    # Get initial record count
    print("Checking initial record count...")
    initial_count = get_record_count(client)
    print(f"Initial records: {format_number(initial_count)}")
    print()
    
    # Create write API with optimized async batching
    # This significantly improves throughput (2-3x) by pipelining writes
    use_async = os.getenv("INFLUXDB_USE_ASYNC", "true").lower() == "true"
    
    if use_async:
        print(f"{BLUE}Using asynchronous batching for better performance{NC}")
        write_options = WriteOptions(
            batch_size=10_000,        # Larger batches for better throughput
            flush_interval=5_000,     # Flush every 5 seconds
            jitter_interval=2_000,    # Add jitter to smooth out write spikes
            retry_interval=5_000,     # Retry failed writes after 5s
            max_retries=3,            # Retry up to 3 times
            max_retry_delay=30_000,   # Max 30s delay between retries
            exponential_base=2        # Exponential backoff
        )
        write_api = client.write_api(write_options=write_options)
    else:
        print(f"{YELLOW}Using synchronous writes (slower but simpler){NC}")
        write_api = client.write_api(write_options=SYNCHRONOUS)
    
    # Ingest files
    print("=" * 50)
    print("Starting ingestion...")
    print("=" * 50)
    print()
    
    overall_start = time.time()
    total_records = 0
    total_bytes = 0
    
    for i, filepath in enumerate(json_files, 1):
        print(f"[{i}/{len(json_files)}]")
        records, size_bytes, elapsed = ingest_file(client, write_api, filepath, use_async)
        total_records += records
        total_bytes += size_bytes
        print()
    
    # Final flush for async mode to ensure all data is written
    if use_async:
        print("Flushing remaining writes...")
        write_api.flush()
    
    overall_elapsed = time.time() - overall_start
    
    # Get final record count
    print("Checking final record count...")
    final_count = get_record_count(client)
    records_inserted = max(final_count - initial_count, total_records)  # Use max in case count query fails
    
    # Print final statistics
    print()
    print("=" * 50)
    print(f"{GREEN}✓ Ingestion Complete!{NC}")
    print("=" * 50)
    print()
    print("Statistics:")
    print(f"  Files processed:    {len(json_files)}")
    print(f"  Total data:         {total_bytes / 1024 / 1024:.2f} MB")
    print(f"  Records inserted:   {format_number(records_inserted)}")
    print(f"  Total time:         {overall_elapsed:.1f} seconds")
    
    if overall_elapsed > 0:
        avg_throughput_mb = (total_bytes / 1024 / 1024) / overall_elapsed
        avg_throughput_rows = total_records / overall_elapsed
        print(f"  Avg throughput:     {avg_throughput_mb:.2f} MB/s")
        print(f"  Avg insert rate:    {format_number(int(avg_throughput_rows))} rows/s")
    
    print()
    print(f"Final record count:   {format_number(final_count)}")
    print()
    print("Next steps:")
    print(f"  - Verify data: curl -XPOST '{INFLUXDB_URL}/api/v2/query?org={INFLUXDB_ORG}' \\")
    print(f"      -H 'Authorization: Token {INFLUXDB_TOKEN[:10]}...' \\")
    print(f"      -H 'Content-Type: application/vnd.flux' \\")
    print(f"      -d 'from(bucket:\"{INFLUXDB_BUCKET}\") |> range(start: 0) |> limit(n: 10)'")
    print()
    
    # Close write API and connection
    if use_async:
        write_api.close()
    client.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Interrupted by user{NC}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{RED}FATAL ERROR: {e}{NC}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

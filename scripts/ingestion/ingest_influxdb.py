#!/usr/bin/env python3
"""
Script: ingest_influxdb.py
Purpose: Streamlined InfluxDB data ingestion with benchmarking
Usage: python ingest_influxdb.py [data_directory]
"""

import os
import sys
import json
import time
import glob
import subprocess
from datetime import datetime

try:
    from influxdb_client import InfluxDBClient, Point
    from influxdb_client.client.write_api import SYNCHRONOUS, WriteOptions
except ImportError:
    print("ERROR: influxdb-client library not found!")
    print("Install it with: pip install influxdb-client")
    sys.exit(1)

# Configuration
INFLUXDB_URL = os.getenv("INFLUXDB_URL", "http://localhost:8086")
INFLUXDB_TOKEN = os.getenv("INFLUXDB_TOKEN", "my-super-secret-auth-token")
INFLUXDB_ORG = os.getenv("INFLUXDB_ORG", "netflow")
INFLUXDB_BUCKET = os.getenv("INFLUXDB_BUCKET", "flows")
CONTAINER_NAME = "influxdb"
DATA_PATH = "/var/lib/influxdb2"

def get_storage():
    """Get InfluxDB storage size in Bytes using docker exec du"""
    cmd = ["docker", "exec", CONTAINER_NAME, "du", "-sb", DATA_PATH]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        size_bytes = int(result.stdout.split()[0])
        return size_bytes
    return 0

def convert_json_to_point(record):
    """Convert JSON flow record to InfluxDB Point"""
    ts = datetime.strptime(record['timestamp'], '%Y-%m-%d %H:%M:%S')
    
    protocol_map = {1: 'ICMP', 6: 'TCP', 17: 'UDP'}
    protocol_num = record['protocol']
    protocol_name = protocol_map.get(protocol_num, 'Other')
    
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


def ingest_file(write_api, filepath):
    """Ingest a single JSON file into InfluxDB"""
    batch = []
    batch_size = 5000
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            record = json.loads(line)
            point = convert_json_to_point(record)
            batch.append(point)
            
            if len(batch) >= batch_size:
                write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=batch)
                batch = []
    
    if batch:
        write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=batch)

def compact_data():
    """
    Trigger InfluxDB compaction.
    InfluxDB 2.x performs automatic compaction in background.
    We'll trigger a snapshot to force persistence.
    """
    # Wait for background compaction to complete
    time.sleep(3)
    
    # Trigger backup which forces a snapshot/compaction
    cmd = ["docker", "exec", CONTAINER_NAME, "influx", "backup", "/tmp/backup_trigger", "-t", INFLUXDB_TOKEN]
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # Clean up
    cmd = ["docker", "exec", CONTAINER_NAME, "rm", "-rf", "/tmp/backup_trigger"]
    subprocess.run(cmd, capture_output=True, text=True)
    
    # Wait for compaction to settle
    time.sleep(2)


def main():
    # Determine data directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_data_dir = os.path.join(script_dir, "../../data-gen/output")
    data_dir = sys.argv[1] if len(sys.argv) > 1 else default_data_dir
    data_dir = os.path.abspath(data_dir)
    
    # Find JSON files
    json_files = sorted(glob.glob(os.path.join(data_dir, "flows_*.json")))
    if not json_files:
        print(f"ERROR: No flows_*.json files found in {data_dir}")
        sys.exit(1)
    
    # Step 0: Measure initial storage (before ingestion)
    initial_storage = get_storage()
    
    # Connect to InfluxDB
    client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
    
    # Use SYNCHRONOUS writes for accurate benchmarking
    # Async mode doesn't guarantee immediate disk persistence
    write_api = client.write_api(write_options=SYNCHRONOUS)
    
    # Step 1: Ingest
    print("Ingesting...")
    start_ns = time.perf_counter_ns()
    
    for filepath in json_files:
        ingest_file(write_api, filepath)
    
    # Close write API to ensure all data is flushed
    write_api.close()
    
    end_ns = time.perf_counter_ns()
    ingest_time_ms = (end_ns - start_ns) / 1_000_000
    
    # Step 2: Measure storage after ingestion (before compaction)
    after_ingest_storage = get_storage()

    # Calculate data size from ingestion (delta)
    ingested_data_size = after_ingest_storage - initial_storage
    
    # Step 3: Compact
    print("Compacting...")
    start_ns = time.perf_counter_ns()
    
    compact_data()
    
    end_ns = time.perf_counter_ns()
    compact_time_ms = (end_ns - start_ns) / 1_000_000
    
    # Step 4: Measure storage after compaction
    after_compact_storage = get_storage()

    # Calculate final data size (delta from initial)
    final_data_size = after_compact_storage - initial_storage
    
    # Calculate compression ratio (reduction from pre-compact to post-compact)
    if ingested_data_size > 0:
        compression_ratio = ((ingested_data_size - final_data_size) / ingested_data_size * 100)
    else:
        compression_ratio = 0.0
    
    # Write output to file
    output_dir = os.path.join(script_dir, "../../benchmark-results/ingest")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "ingest-influxdb-output.txt")
    
    with open(output_path, 'w') as f:
        f.write(f"Ingestion Time: {ingest_time_ms:.3f} ms\n")
        f.write(f"Pre-compaction Storage: {ingested_data_size:.2f} Bytes\n")
        f.write(f"Compaction Time: {compact_time_ms:.3f} ms\n")
        f.write(f"Post-compaction Storage: {final_data_size:.2f} Bytes\n")
        f.write(f"Compression Ratio: {compression_ratio:.2f}%\n")
    
    # Cleanup (write_api already closed before measurement)
    client.close()
    
    print(f"Done. Results written to {output_path}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)

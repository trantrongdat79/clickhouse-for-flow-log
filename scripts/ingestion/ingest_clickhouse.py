#!/usr/bin/env python3
"""
Script: ingest_clickhouse.py
Purpose: Streamlined ClickHouse data ingestion with benchmarking
Usage: python ingest_clickhouse.py [data_directory]
"""

import os
import sys
import time
import glob
import subprocess
import requests

# Configuration
CH_HOST = os.getenv("CH_HOST", "localhost")
CH_PORT = os.getenv("CH_PORT", "8123")
CH_DB = os.getenv("CH_DB", "netflow")
CH_TABLE = os.getenv("CH_TABLE", "flows_local")
CH_USER = os.getenv("CH_USER", "default")
CH_PASSWORD = os.getenv("CH_PASSWORD", "admin")
CONTAINER_NAME = "clickhouse01"
DATA_PATH = "/var/lib/clickhouse"


def get_storage():
    """Get ClickHouse storage size in bytes using docker exec du"""
    cmd = ["docker", "exec", CONTAINER_NAME, "du", "-sb", DATA_PATH]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        size_bytes = int(result.stdout.split()[0])
        return size_bytes
    return 0


def ingest_file(filepath):
    """Ingest a single JSON file into ClickHouse"""
    url = f"http://{CH_HOST}:{CH_PORT}/"
    query = f"INSERT INTO {CH_DB}.{CH_TABLE} FORMAT JSONEachRow"
    
    with open(filepath, 'rb') as f:
        response = requests.post(
            url,
            params={'query': query},
            data=f,
            auth=(CH_USER, CH_PASSWORD),
            timeout=300
        )
    
    if response.status_code != 200 or "Exception" in response.text:
        print(f"ERROR: {response.text}")
        sys.exit(1)


def compact_table():
    """Run OPTIMIZE TABLE FINAL to compact data"""
    url = f"http://{CH_HOST}:{CH_PORT}/"
    query = f"OPTIMIZE TABLE {CH_DB}.{CH_TABLE} FINAL"
    
    response = requests.post(
        url,
        params={'query': query},
        auth=(CH_USER, CH_PASSWORD),
        timeout=600
    )
    
    if response.status_code != 200:
        print(f"ERROR: {response.text}")
        sys.exit(1)

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
    
    # Step 1: Ingest
    print("Ingesting...")
    start_ns = time.perf_counter_ns()
    
    for filepath in json_files:
        ingest_file(filepath)
    
    end_ns = time.perf_counter_ns()
    ingest_time_ms = (end_ns - start_ns) / 1_000_000
            
    # Step 2: Measure storage after ingestion (before compaction)
    after_ingest_storage = get_storage()
    
    # Calculate data size from ingestion (delta)
    ingested_data_size = after_ingest_storage - initial_storage
    
    # Step 3: Compact
    print("Compacting...")
    start_ns = time.perf_counter_ns()
    
    compact_table()
    
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
    output_path = os.path.join(output_dir, "ingest-clickhouse-output.txt")
    
    with open(output_path, 'w') as f:
        f.write(f"Ingestion Time: {ingest_time_ms:.3f} ms\n")
        f.write(f"Pre-compaction Storage: {ingested_data_size:.2f} Bytes\n")
        f.write(f"Compaction Time: {compact_time_ms:.3f} ms\n")
        f.write(f"Post-compaction Storage: {final_data_size:.2f} Bytes\n")
        f.write(f"Compression Ratio: {compression_ratio:.2f}%\n")
    
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

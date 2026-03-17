#!/bin/bash
# Script: ingest_influxdb.sh
# Purpose: Wrapper script for InfluxDB ingestion (calls Python script)
# Usage: ./ingest_influxdb.sh [data_directory]
# Author: NetFlow Analytics Team
# Date: 2026-03-16

set -e  # Exit on error

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export InfluxDB configuration (can be overridden via environment)
export INFLUXDB_URL="${INFLUXDB_URL:-http://localhost:8086}"
export INFLUXDB_TOKEN="${INFLUXDB_TOKEN:-my-super-secret-auth-token}"
export INFLUXDB_ORG="${INFLUXDB_ORG:-netflow}"
export INFLUXDB_BUCKET="${INFLUXDB_BUCKET:-flows}"

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "ERROR: python3 is required but not installed"
    exit 1
fi

# Check if influxdb-client is installed
if ! python3 -c "import influxdb_client" 2>/dev/null; then
    echo "ERROR: influxdb-client library not found"
    echo "Install it with: pip3 install influxdb-client"
    exit 1
fi

# Run the Python ingestion script
exec python3 "${SCRIPT_DIR}/ingest_influxdb.py" "$@"

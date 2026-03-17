#!/bin/bash
# Script: cleanup_all.sh
# Purpose: Reset the project to a clean state (like a fresh clone)
# Usage: ./cleanup_all.sh [--confirm]
# Author: NetFlow Analytics Team
# Date: 2026-03-16

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Project Cleanup Script${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "This script will clean up ALL data and reset the project to a fresh state."
echo ""
echo -e "${YELLOW}Warning: This will remove:${NC}"
echo "  - All Docker containers and volumes"
echo "  - All generated data files"
echo "  - All logs"
echo "  - All backups"
echo "  - InfluxDB data directories"
echo "  - Grafana data directories"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""

# Check if --confirm flag is provided
if [ "$1" != "--confirm" ]; then
    read -p "Are you sure you want to continue? (yes/no): " response
    if [ "$response" != "yes" ]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

echo ""
echo -e "${BOLD}Starting cleanup...${NC}"
echo ""

# Step 1: Stop and remove Docker containers
echo -e "${BLUE}[1/7]${NC} Stopping Docker containers..."
cd "${PROJECT_ROOT}/docker"
if docker compose ps -q > /dev/null 2>&1; then
    docker compose down -v --remove-orphans
    echo -e "${GREEN}✓${NC} Docker containers stopped and removed"
else
    echo -e "${YELLOW}⊘${NC} No running containers found"
fi
echo ""

# Step 2: Remove Docker volumes
echo -e "${BLUE}[2/7]${NC} Removing Docker volumes..."
# List volumes that might exist
volumes=(
    "docker_clickhouse_data"
)

removed_count=0
for volume in "${volumes[@]}"; do
    if docker volume ls -q | grep -q "^${volume}$"; then
        docker volume rm "${volume}" 2>/dev/null && removed_count=$((removed_count + 1))
    fi
done

if [ $removed_count -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Removed ${removed_count} Docker volume(s)"
else
    echo -e "${YELLOW}⊘${NC} No Docker volumes found"
fi
echo ""

# Step 3: Clean data directories
echo -e "${BLUE}[3/7]${NC} Cleaning data directories..."
data_cleaned=0

# InfluxDB data
if [ -d "${PROJECT_ROOT}/data/influxdb" ]; then
    rm -rf "${PROJECT_ROOT}/data/influxdb"/*
    echo "  - Cleaned: data/influxdb/"
    data_cleaned=1
fi

# Clickhouse data
if [ -d "${PROJECT_ROOT}/data/" ]; then
    rm -rf "${PROJECT_ROOT}/data/clickhouse*"/*
    echo "  - Cleaned: data/clickhouse/"
    data_cleaned=1
fi

# Grafana data
if [ -d "${PROJECT_ROOT}/data/grafana" ]; then
    rm -rf "${PROJECT_ROOT}/data/grafana"/*
    echo "  - Cleaned: data/grafana/"
    data_cleaned=1
fi

# Generated flow data
if [ -d "${PROJECT_ROOT}/data-gen/output" ]; then
    rm -rf "${PROJECT_ROOT}/data-gen/output"/*
    echo "  - Cleaned: data-gen/output/"
    data_cleaned=1
fi

if [ $data_cleaned -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Data directories cleaned"
else
    echo -e "${YELLOW}⊘${NC} No data to clean"
fi
echo ""

# Step 4: Clean log directories
echo -e "${BLUE}[4/7]${NC} Cleaning log directories..."
logs_cleaned=0

for logdir in clickhouse01 influxdb grafana; do
    if [ -d "${PROJECT_ROOT}/logs/${logdir}" ]; then
        rm -rf "${PROJECT_ROOT}/logs/${logdir}"/*
        echo "  - Cleaned: logs/${logdir}/"
        logs_cleaned=1
    fi
done

if [ $logs_cleaned -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Log directories cleaned"
else
    echo -e "${YELLOW}⊘${NC} No logs to clean"
fi
echo ""

# Step 5: Clean backup directories
echo -e "${BLUE}[5/7]${NC} Cleaning backup directories..."
backups_cleaned=0

for backupdir in clickhouse influxdb grafana; do
    if [ -d "${PROJECT_ROOT}/backups/${backupdir}" ]; then
        rm -rf "${PROJECT_ROOT}/backups/${backupdir}"/*
        echo "  - Cleaned: backups/${backupdir}/"
        backups_cleaned=1
    fi
done

if [ $backups_cleaned -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Backup directories cleaned"
else
    echo -e "${YELLOW}⊘${NC} No backups to clean"
fi
echo ""

# Step 6: Clean benchmark results
echo -e "${BLUE}[6/7]${NC} Cleaning benchmark results..."
if [ -d "${PROJECT_ROOT}/benchmark-results" ]; then
    # Keep directory structure but remove result files
    find "${PROJECT_ROOT}/benchmark-results" -type f -name "*.json" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}/benchmark-results" -type f -name "*.txt" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}/benchmark-results" -type f -name "*.csv" -delete 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Benchmark results cleaned"
else
    echo -e "${YELLOW}⊘${NC} No benchmark results to clean"
fi
echo ""

# Step 7: Clean Python cache and temporary files
echo -e "${BLUE}[7/7]${NC} Cleaning Python cache and temporary files..."
cache_cleaned=0

# Remove __pycache__ directories
if find "${PROJECT_ROOT}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null; then
    cache_cleaned=1
fi

# Remove .pyc files
if find "${PROJECT_ROOT}" -type f -name "*.pyc" -delete 2>/dev/null; then
    cache_cleaned=1
fi

# Remove temporary files
if [ -f "/tmp/ch_insert_result.txt" ]; then
    rm -f /tmp/ch_insert_result.txt
    cache_cleaned=1
fi

if [ $cache_cleaned -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Cache and temporary files cleaned"
else
    echo -e "${YELLOW}⊘${NC} No cache to clean"
fi
echo ""

# Summary
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}✓ Cleanup Complete!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "The project has been reset to a clean state."
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Start services:     cd docker && docker compose up -d"
echo "  2. Initialize schema:  cd scripts/setup && ./02-init-schema.sh"
echo "  3. Generate data:      cd data-gen && python3 generate_flows.py"
echo "  4. Ingest data:        cd scripts/ingestion && ./ingest_clickhouse.sh"
echo ""
echo "See QUICKSTART_GUIDE.md for detailed instructions."
echo ""

# Optional: Show disk space freed
if command -v df &> /dev/null; then
    echo -e "${BLUE}Current disk usage:${NC}"
    df -h "${PROJECT_ROOT}" | tail -1
    echo ""
fi

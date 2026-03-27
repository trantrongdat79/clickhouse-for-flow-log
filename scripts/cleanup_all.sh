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
docker compose down -v --remove-orphans

# Step 2: Remove Docker volumes
echo -e "${BLUE}[2/7]${NC} Removing Docker volumes..."
# List volumes that might exist
volumes=(
    "docker_clickhouse_data"
)

for volume in "${volumes[@]}"; do
    docker volume rm "${volume}" || true
done

# Step 3: Clean data directories
echo -e "${BLUE}[3/7]${NC} Cleaning data directories..."
data_cleaned=0

# InfluxDB data
rm -rf "${PROJECT_ROOT}/data/influxdb"/*
echo "  - Cleaned: data/influxdb/"

# Clickhouse data
rm -rf "${PROJECT_ROOT}/data/clickhouse*"/*
echo "  - Cleaned: data/clickhouse/"

# Grafana data
rm -rf "${PROJECT_ROOT}/data/grafana"/*
echo "  - Cleaned: data/grafana/"

# Generated flow data
rm -rf "${PROJECT_ROOT}/data-gen/output"/*
echo "  - Cleaned: data-gen/output/"

echo -e "${GREEN}✓${NC} Data directories cleaned"
echo ""

# Step 4: Clean log directories
echo -e "${BLUE}[4/7]${NC} Cleaning log directories..."

for logdir in clickhouse01 influxdb grafana; do
    rm -rf "${PROJECT_ROOT}/logs/${logdir}"/*
    echo "  - Cleaned: logs/${logdir}/"
done

echo -e "${GREEN}✓${NC} Log directories cleaned"
echo ""

# Step 5: Clean backup directories
echo -e "${BLUE}[5/7]${NC} Cleaning backup directories..."

for backupdir in clickhouse influxdb grafana; do
    rm -rf "${PROJECT_ROOT}/backups/${backupdir}"/*
    echo "  - Cleaned: backups/${backupdir}/"
done

echo ""

# Step 6: Clean benchmark results
echo -e "${BLUE}[6/7]${NC} Cleaning benchmark results..."
# Keep directory structure but remove result files
find "${PROJECT_ROOT}/benchmark-results" -type f -name "*.json" -delete 2>/dev/null || true
find "${PROJECT_ROOT}/benchmark-results" -type f -name "*.txt" -delete 2>/dev/null || true
find "${PROJECT_ROOT}/benchmark-results" -type f -name "*.csv" -delete 2>/dev/null || true

echo ""

# Step 7: Clean Python cache and temporary files
echo -e "${BLUE}[7/7]${NC} Cleaning Python cache and temporary files..."
cache_cleaned=0

# Remove __pycache__ directories
find "${PROJECT_ROOT}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
# Remove .pyc files
find "${PROJECT_ROOT}" -type f -name "*.pyc" -delete 2>/dev/null || true

# Remove temporary files
rm -f /tmp/ch_insert_result.txt

echo ""

# Summary
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}✓ Cleanup Complete!${NC}"
echo -e "${BOLD}========================================${NC}"
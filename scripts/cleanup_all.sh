#!/bin/bash
# Script: cleanup_all.sh
# Purpose: Reset the project to a clean state (like a fresh clone)
# Usage: ./cleanup_all.sh [--confirm]
# Author: NetFlow Analytics Team
# Date: 2026-03-16

set -euo pipefail

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

clean_dir_contents() {
    local dir="$1"
    if [ -d "$dir" ]; then
        # First try with current user permissions.
        find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

        # If files remain (often root/container-owned), try sudo when available.
        if [ -n "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]; then
            if command -v sudo >/dev/null 2>&1; then
                sudo find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
            fi
        fi

        # Emit a warning if cleanup is still incomplete.
        if [ -n "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]; then
            echo -e "${YELLOW}  ! Warning: Could not fully clean ${dir} (permission denied)${NC}"
        fi
    fi
}

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Project Cleanup Script${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "This script cleans runtime data and resets the project environment."
echo ""
echo -e "${YELLOW}Warning: This will remove:${NC}"
echo "  - All Docker containers and volumes"
echo "  - All generated data files"
echo "  - All logs"
echo "  - All backups"
echo "  - Benchmark output files"
echo "  - Python cache files"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""

# Check if --confirm flag is provided
if [ "${1:-}" != "--confirm" ]; then
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
(
    cd "${PROJECT_ROOT}/docker"
    docker compose down -v --remove-orphans
)

echo -e "${GREEN}✓${NC} Containers and volumes removed"
echo ""

# Step 2: Clean data directories
echo -e "${BLUE}[2/7]${NC} Cleaning data directories..."

# InfluxDB data
clean_dir_contents "${PROJECT_ROOT}/data/influxdb"
echo "  - Cleaned: data/influxdb/"

# Clickhouse data
clean_dir_contents "${PROJECT_ROOT}/data/clickhouse"
echo "  - Cleaned: data/clickhouse/ (if present)"

# Grafana data
clean_dir_contents "${PROJECT_ROOT}/data/grafana"
echo "  - Cleaned: data/grafana/"

# Generated flow data
find "${PROJECT_ROOT}/data-gen/output" -type f -name "*.json" -delete 2>/dev/null || true
echo "  - Cleaned: data-gen/output/"

echo -e "${GREEN}✓${NC} Data directories cleaned"
echo ""

# Step 3: Clean log directories
echo -e "${BLUE}[3/7]${NC} Cleaning log directories..."

for logdir in clickhouse01 clickhouse02 influxdb grafana; do
    clean_dir_contents "${PROJECT_ROOT}/logs/${logdir}"
    echo "  - Cleaned: logs/${logdir}/"
done

echo -e "${GREEN}✓${NC} Log directories cleaned"
echo ""

# Step 4: Clean backup directories
echo -e "${BLUE}[4/7]${NC} Cleaning backup directories..."

for backupdir in clickhouse influxdb grafana; do
    clean_dir_contents "${PROJECT_ROOT}/backups/${backupdir}"
    echo "  - Cleaned: backups/${backupdir}/"
done

echo ""

# Step 5: Clean benchmark results
echo -e "${BLUE}[5/7]${NC} Cleaning benchmark results..."
# Keep directory structure but remove result files
find "${PROJECT_ROOT}/benchmark-results" -type f \( -name "*.json" -o -name "*.txt" -o -name "*.csv" \) -delete 2>/dev/null || true

echo -e "${GREEN}✓${NC} Benchmark files cleaned"
echo ""

# Step 6: Clean Python cache
echo -e "${BLUE}[6/7]${NC} Cleaning Python cache..."

find "${PROJECT_ROOT}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${PROJECT_ROOT}" -type f -name "*.pyc" -delete 2>/dev/null || true

echo -e "${GREEN}✓${NC} Python cache cleaned"
echo ""

# Step 7: Clean temporary files
echo -e "${BLUE}[7/7]${NC} Cleaning temporary files..."

# Remove temporary files
rm -f /tmp/ch_insert_result.txt /tmp/ch_init.log 2>/dev/null || true

echo -e "${GREEN}✓${NC} Temporary files cleaned"

echo ""

# Summary
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}✓ Cleanup Complete!${NC}"
echo -e "${BOLD}========================================${NC}"
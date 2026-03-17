#!/usr/bin/env python3
"""
Script: estimate_cardinality.py
Purpose: Estimate InfluxDB series cardinality for NetFlow data configuration
Usage: python estimate_cardinality.py --src-ips 10000 --dst-ips 50000
Author: NetFlow Analytics Team
Date: 2026-03-16

This tool helps predict InfluxDB performance by estimating series cardinality
BEFORE generating and ingesting expensive test datasets.
"""

import argparse
import sys
from typing import Tuple

# ANSI color codes
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
BOLD = '\033[1m'
NC = '\033[0m'

# Port distribution estimates based on realistic NetFlow data
# In real NetFlow data, not all port combinations exist
# Additionally, not all IP pairs communicate (traffic is sparse)
SPARSITY_FACTOR = 0.1  # Only ~10% of possible IP pairs have traffic
AVG_PORT_COMBOS_PER_ACTIVE_PAIR = 5  # Average unique (src_port, dst_port) per active flow


def estimate_theoretical_cardinality(src_ips: int, dst_ips: int) -> Tuple[int, int, int]:
    """
    Estimate theoretical max and realistic cardinality.
    
    Tags in InfluxDB: src_ip, dst_ip, protocol, protocol_name, src_port, dst_port
    
    Returns:
        (theoretical_max, realistic_worst, realistic_typical)
    """
    protocols = 3  # TCP, UDP, ICMP
    max_src_ports = 65535
    max_dst_ports = 65535
    
    # Theoretical maximum (if ALL combinations existed - never happens in practice)
    theoretical_max = src_ips * dst_ips * protocols * max_src_ports * max_dst_ports
    
    # Realistic worst case (high diversity, all IP pairs active)
    # Each active IP pair averages 20 unique port combinations
    realistic_worst = src_ips * dst_ips * protocols * 20
    
    # Realistic typical case (sparse traffic, common patterns)
    # Only 10% of IP pairs are active, each with ~5 port combinations
    realistic_typical = int(src_ips * dst_ips * SPARSITY_FACTOR * protocols * AVG_PORT_COMBOS_PER_ACTIVE_PAIR)
    
    return theoretical_max, realistic_worst, realistic_typical


def classify_cardinality(cardinality: int) -> Tuple[str, str, str]:
    """
    Classify cardinality level and predict InfluxDB performance.
    
    Returns:
        (status, influxdb_perf, clickhouse_perf)
    """
    if cardinality < 100_000:
        return "OPTIMAL", "Excellent (fast writes, low memory)", "Excellent (even faster)"
    elif cardinality < 500_000:
        return "GOOD", "Good (acceptable performance)", "Excellent (5-10x faster)"
    elif cardinality < 1_000_000:
        return "ACCEPTABLE", "Fair (approaching limits, slower)", "Excellent (10-15x faster)"
    elif cardinality < 5_000_000:
        return "WARNING", "Degraded (noticeable slowdown)", "Excellent (20-30x faster)"
    elif cardinality < 20_000_000:
        return "CRITICAL", "Severely impaired (very slow)", "Excellent (50-100x faster)"
    else:
        return "FAILURE", "Likely to fail (OOM or timeout)", "Excellent (stable performance)"


def format_number(n: int) -> str:
    """Format number with thousand separators"""
    return f"{n:,}"


def print_banner():
    """Print script banner"""
    print(f"{CYAN}{'=' * 70}{NC}")
    print(f"{CYAN}  InfluxDB Cardinality Estimator for NetFlow Data{NC}")
    print(f"{CYAN}{'=' * 70}{NC}")
    print()


def print_estimation(src_ips: int, dst_ips: int, records: int):
    """Print detailed cardinality estimation"""
    print(f"{BOLD}Input Configuration:{NC}")
    print(f"  Source IPs:      {format_number(src_ips)}")
    print(f"  Destination IPs: {format_number(dst_ips)}")
    print(f"  Records:         {format_number(records)}")
    print()
    
    # Calculate estimates
    theoretical, worst, typical = estimate_theoretical_cardinality(src_ips, dst_ips)
    
    # Classify typical case (most realistic)
    status, influx_perf, clickhouse_perf = classify_cardinality(typical)
    
    # Color-code status
    status_colors = {
        "OPTIMAL": GREEN,
        "GOOD": GREEN,
        "ACCEPTABLE": YELLOW,
        "WARNING": YELLOW,
        "CRITICAL": RED,
        "FAILURE": RED
    }
    status_color = status_colors.get(status, NC)
    
    print(f"{BOLD}Cardinality Estimates:{NC}")
    print(f"  Theoretical Max:     {CYAN}{format_number(theoretical)}{NC} series")
    print(f"    (Impossible - all IP×port combinations: {src_ips}×{dst_ips}×3×65K×65K)")
    print()
    print(f"  Realistic Worst:     {YELLOW}{format_number(worst)}{NC} series")
    print(f"    (All IP pairs active: {src_ips}×{dst_ips}×3×20 ports)")
    print()
    print(f"  Realistic Typical:   {status_color}{BOLD}{format_number(typical)}{NC} series")
    print(f"    (Sparse traffic: ~10% IP pairs active, ~5 ports each)")
    print()
    
    print(f"{BOLD}Performance Prediction:{NC}")
    print(f"  Status:              {status_color}{BOLD}{status}{NC}")
    print()
    print(f"  InfluxDB:            {influx_perf}")
    print(f"  ClickHouse:          {clickhouse_perf}")
    print()
    
    # Recommendations
    print(f"{BOLD}Recommendations:{NC}")
    if status in ["OPTIMAL", "GOOD"]:
        print(f"  {GREEN}✓{NC} Safe to run - both systems will perform well")
        print(f"  {GREEN}✓{NC} Good baseline for comparison")
    elif status == "ACCEPTABLE":
        print(f"  {YELLOW}⚠{NC} InfluxDB approaching limits - expect slowdown")
        print(f"  {YELLOW}⚠{NC} ClickHouse will demonstrate clear advantage")
    elif status == "WARNING":
        print(f"  {YELLOW}⚠{NC} InfluxDB will struggle - significant degradation expected")
        print(f"  {YELLOW}⚠{NC} Good for demonstrating cardinality issues")
        print(f"  {YELLOW}⚠{NC} Consider reducing IPs if quick results needed")
    elif status == "CRITICAL":
        print(f"  {RED}⚠{NC} InfluxDB severely impaired - may take hours or fail")
        print(f"  {RED}⚠{NC} Excellent for showing ClickHouse superiority")
        print(f"  {RED}⚠{NC} Be prepared for long wait times or timeouts")
    else:  # FAILURE
        print(f"  {RED}✗{NC} InfluxDB likely to fail (OOM or extreme slowness)")
        print(f"  {RED}✗{NC} Only run if you want to demonstrate failure")
        print(f"  {RED}✗{NC} Ensure adequate timeout settings")
    print()
    
    # Memory estimates
    print(f"{BOLD}Estimated Memory Requirements:{NC}")
    
    # InfluxDB: roughly 150-300 bytes per series in TSI index
    influx_memory_mb = (typical * 250) // (1024 * 1024)
    print(f"  InfluxDB TSI Index:  ~{format_number(influx_memory_mb)} MB")
    
    # ClickHouse: roughly 30 bytes per 1M rows for metadata
    ch_memory_mb = (records * 30) // (1024 * 1024)
    print(f"  ClickHouse Metadata: ~{format_number(ch_memory_mb)} MB")
    print()
    
    # Estimated runtime
    print(f"{BOLD}Estimated Ingestion Time:{NC}")
    
    # ClickHouse: typically 100K-500K rows/sec depending on hardware
    ch_rate_low = 100_000
    ch_rate_high = 500_000
    ch_time_low = records / ch_rate_high
    ch_time_high = records / ch_rate_low
    
    print(f"  ClickHouse:          {format_time(ch_time_low)} - {format_time(ch_time_high)}")
    
    # InfluxDB: varies dramatically by cardinality
    if status in ["OPTIMAL", "GOOD"]:
        influx_rate = 50_000
        influx_time = records / influx_rate
        print(f"  InfluxDB:            ~{format_time(influx_time)}")
    elif status == "ACCEPTABLE":
        influx_rate = 20_000
        influx_time = records / influx_rate
        print(f"  InfluxDB:            ~{format_time(influx_time)} (2-3x slower)")
    elif status == "WARNING":
        influx_rate = 5_000
        influx_time = records / influx_rate
        print(f"  InfluxDB:            ~{format_time(influx_time)} (10-20x slower)")
    elif status == "CRITICAL":
        influx_rate = 1_000
        influx_time = records / influx_rate
        print(f"  InfluxDB:            ~{format_time(influx_time)} (50-100x slower)")
    else:
        print(f"  InfluxDB:            {RED}May timeout or fail{NC}")
    print()


def format_time(seconds: float) -> str:
    """Format seconds into human-readable time"""
    if seconds < 60:
        return f"{int(seconds)}s"
    elif seconds < 3600:
        minutes = int(seconds / 60)
        return f"{minutes}m"
    else:
        hours = int(seconds / 3600)
        minutes = int((seconds % 3600) / 60)
        return f"{hours}h {minutes}m"


def compare_levels():
    """Print comparison table of all benchmark levels"""
    levels = [
        ("Low", 100, 100, 1_000_000),
        ("Medium", 200, 200, 4_000_000),
    ]
    
    print(f"{CYAN}{'=' * 70}{NC}")
    print(f"{CYAN}  Benchmark Level Comparison{NC}")
    print(f"{CYAN}{'=' * 70}{NC}")
    print()
    
    print(f"{'Level':<12} {'Src IPs':>10} {'Dst IPs':>10} {'Records':>12} {'Est. Series':>15} {'Status':<12}")
    print(f"{'-' * 80}")
    
    for name, src, dst, recs in levels:
        _, _, typical = estimate_theoretical_cardinality(src, dst)
        status, _, _ = classify_cardinality(typical)
        
        status_colors = {
            "OPTIMAL": GREEN,
            "GOOD": GREEN,
            "ACCEPTABLE": YELLOW,
            "WARNING": YELLOW,
            "CRITICAL": RED,
            "FAILURE": RED
        }
        color = status_colors.get(status, NC)
        
        print(f"{name:<12} {src:>10,} {dst:>10,} {recs:>12,} {typical:>15,} {color}{status:<12}{NC}")
    
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Estimate InfluxDB series cardinality for NetFlow data",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Estimate for baseline test
  python estimate_cardinality.py --src-ips 100 --dst-ips 500 --records 1000000
  
  # Estimate for critical test
  python estimate_cardinality.py --src-ips 10000 --dst-ips 50000 --records 100000000
  
  # Compare all benchmark levels
  python estimate_cardinality.py --compare
        """
    )
    
    parser.add_argument('--src-ips', type=int, help='Number of unique source IPs')
    parser.add_argument('--dst-ips', type=int, help='Number of unique destination IPs')
    parser.add_argument('--records', type=int, default=1_000_000, help='Total number of records')
    parser.add_argument('--compare', action='store_true', help='Show comparison of all benchmark levels')
    
    args = parser.parse_args()
    
    print_banner()
    
    if args.compare:
        compare_levels()
    elif args.src_ips and args.dst_ips:
        print_estimation(args.src_ips, args.dst_ips, args.records)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()

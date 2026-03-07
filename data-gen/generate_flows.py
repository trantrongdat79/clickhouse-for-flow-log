#!/usr/bin/env python3
"""
Module: generate_flows.py
Purpose: Generate synthetic NetFlow data for testing ClickHouse performance
Usage: python generate_flows.py --records 1000000 --output output/

Dependencies:
    - Python 3.8+
    - Standard library only (no external packages)
    
Configuration:
    - Adjust UNIQUE_SRC_IPS, UNIQUE_DST_IPS for cardinality
    - Modify protocol weights for traffic distribution
    - Change time range for dataset span
"""

import argparse
import json
import random
from datetime import datetime, timedelta
from typing import Dict, List

# TODO: Implement data generation logic
#
# Key components:
# 1. IP address pool generation (Pareto distribution - 20% IPs = 80% traffic)
# 2. Port selection (common ports weighted higher)
# 3. Protocol distribution (TCP 70%, UDP 25%, ICMP 5%)
# 4. Flow size (log-normal distribution for realism)
# 5. Temporal patterns (business hours peak)
#
# Configuration constants:
# UNIQUE_SRC_IPS = 100_000 for full scale, 10_000 for testing
# UNIQUE_DST_IPS = 500_000 for full scale, 50_000 for testing
# TOTAL_RECORDS = 250_000_000 for full (75GB), 2_500_000 for test (750MB)
#
# Example output format (JSONEachRow):
# {"timestamp": "2024-01-01 00:00:00", "src_ip": "192.168.1.1", ...}
#
# Performance: Should generate 100K-500K records/sec


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--records', type=int, default=1_000_000,
                        help='Number of flow records to generate')
    parser.add_argument('--output', type=str, default='output/',
                        help='Output directory for generated files')
    parser.add_argument('--unique-src-ips', type=int, default=10_000,
                        help='Number of unique source IPs')
    parser.add_argument('--unique-dst-ips', type=int, default=50_000,
                        help='Number of unique destination IPs')
    
    args = parser.parse_args()
    
    print(f"Generating {args.records:,} flow records...")
    print(f"Cardinality: {args.unique_src_ips:,} src IPs, {args.unique_dst_ips:,} dst IPs")
    
    # TODO: Implement generation
    print("TODO: Implement data generation")
    

if __name__ == '__main__':
    main()

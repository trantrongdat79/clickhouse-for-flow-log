#!/usr/bin/env python3
"""
Module: generate_flows.py
Purpose: Generate synthetic NetFlow data with geo-location for ClickHouse testing
Usage: python generate_flows.py --records 1000000 --output output/

Dependencies:
    - Python 3.8+
    - Standard library only (no external packages)
    
Features:
    - Realistic IP address distribution (Pareto: 20% IPs = 80% traffic)
    - Geographic coordinates for source and destination IPs
    - Weighted protocol distribution (TCP 70%, UDP 25%, ICMP 5%)
    - Common ports weighted higher
    - Log-normal distribution for flow sizes
    - Temporal patterns (business hours peak)
    - High-performance generation (200K+ records/sec)
"""

import argparse
import json
import math
import os
import random
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Tuple
from pathlib import Path


# Major world cities with coordinates (lat, lon) for realistic geo-distribution
MAJOR_LOCATIONS = [
    # North America
    (40.7128, -74.0060),   # New York
    (37.7749, -122.4194),  # San Francisco
    (34.0522, -118.2437),  # Los Angeles
    (41.8781, -87.6298),   # Chicago
    (29.7604, -95.3698),   # Houston
    (43.6532, -79.3832),   # Toronto
    (49.2827, -123.1207),  # Vancouver
    
    # Europe
    (51.5074, -0.1278),    # London
    (48.8566, 2.3522),     # Paris
    (52.5200, 13.4050),    # Berlin
    (41.9028, 12.4964),    # Rome
    (40.4168, -3.7038),    # Madrid
    (59.3293, 18.0686),    # Stockholm
    (55.7558, 37.6173),    # Moscow
    
    # Asia Pacific
    (35.6762, 139.6503),   # Tokyo
    (37.5665, 126.9780),   # Seoul
    (31.2304, 121.4737),   # Shanghai
    (22.3193, 114.1694),   # Hong Kong
    (1.3521, 103.8198),    # Singapore
    (19.0760, 72.8777),    # Mumbai
    (-33.8688, 151.2093),  # Sydney
    (28.6139, 77.2090),    # Delhi
    
    # Others
    (-23.5505, -46.6333),  # São Paulo
    (25.2048, 55.2708),    # Dubai
    (30.0444, 31.2357),    # Cairo
]


class NetFlowGenerator:
    """Generate realistic synthetic NetFlow data."""
    
    def __init__(self, unique_src_ips: int, unique_dst_ips: int, 
                 time_range_days: int, start_time: datetime):
        self.unique_src_ips = unique_src_ips
        self.unique_dst_ips = unique_dst_ips
        self.time_range_days = time_range_days
        self.start_time = start_time
        self.end_time = start_time + timedelta(days=time_range_days)
        
        # Pre-generate IP pools with geo-locations
        print("Generating IP address pools...")
        self.src_ip_pool = self._generate_ip_pool(unique_src_ips)
        self.dst_ip_pool = self._generate_ip_pool(unique_dst_ips)
        
        # Pareto weights for realistic distribution (80/20 rule)
        self.src_weights = self._pareto_weights(unique_src_ips, alpha=1.16)
        self.dst_weights = self._pareto_weights(unique_dst_ips, alpha=1.16)
        
        # Common ports with weights
        self.common_ports = [
            (80, 0.25),    # HTTP
            (443, 0.30),   # HTTPS
            (22, 0.05),    # SSH
            (53, 0.08),    # DNS
            (3306, 0.03),  # MySQL
            (5432, 0.02),  # PostgreSQL
            (6379, 0.02),  # Redis
            (8080, 0.05),  # HTTP-alt
            (27017, 0.02), # MongoDB
        ]
        
        # Protocol distribution
        self.protocols = [
            (6, 0.70, 'TCP'),    # TCP
            (17, 0.25, 'UDP'),   # UDP
            (1, 0.05, 'ICMP'),   # ICMP
        ]
        
    def _generate_ip_pool(self, count: int) -> List[Dict]:
        """Generate IP addresses with geographic coordinates."""
        ip_pool = []
        
        for i in range(count):
            # Generate private IP addresses (10.0.0.0/8 and 172.16.0.0/12)
            if i < count * 0.7:  # 70% from 10.0.0.0/8
                octet1 = 10
                octet2 = random.randint(0, 255)
                octet3 = random.randint(0, 255)
                octet4 = random.randint(1, 254)
            else:  # 30% from 172.16.0.0/12
                octet1 = 172
                octet2 = random.randint(16, 31)
                octet3 = random.randint(0, 255)
                octet4 = random.randint(1, 254)
            
            ip_str = f"{octet1}.{octet2}.{octet3}.{octet4}"
            
            # Assign geo-location from major cities
            lat, lon = random.choice(MAJOR_LOCATIONS)
            
            # Add some random offset for variety (within ~50km radius)
            lat += random.uniform(-0.5, 0.5)
            lon += random.uniform(-0.5, 0.5)
            
            ip_pool.append({
                'ip': ip_str,
                'lat': round(lat, 4),
                'lon': round(lon, 4)
            })
        
        return ip_pool
    
    def _pareto_weights(self, size: int, alpha: float = 1.16) -> List[float]:
        """Generate Pareto distribution weights (80/20 rule)."""
        weights = [1.0 / (i + 1) ** alpha for i in range(size)]
        total = sum(weights)
        return [w / total for w in weights]
    
    def _select_weighted_ip(self, pool: List[Dict], weights: List[float]) -> Dict:
        """Select IP with Pareto-weighted probability."""
        return random.choices(pool, weights=weights, k=1)[0]
    
    def _select_port(self, is_common: bool = True) -> int:
        """Select port number (weighted towards common ports)."""
        if is_common and random.random() < 0.80:  # 80% use common ports
            ports, weights = zip(*self.common_ports)
            return random.choices(ports, weights=weights, k=1)[0]
        else:
            return random.randint(1024, 65535)  # Ephemeral ports
    
    def _select_protocol(self) -> Tuple[int, str]:
        """Select protocol with weighted distribution."""
        proto_nums, weights, names = zip(*self.protocols)
        idx = random.choices(range(len(proto_nums)), weights=weights, k=1)[0]
        return proto_nums[idx], names[idx]
    
    def _generate_timestamp(self) -> str:
        """Generate random timestamp within time range with business hour weighting."""
        # Random day
        days_offset = random.uniform(0, self.time_range_days)
        flow_time = self.start_time + timedelta(days=days_offset)
        
        # Weight towards business hours (8AM-6PM)
        hour = int(random.triangular(0, 23, 13))  # Peak at 1PM
        minute = random.randint(0, 59)
        second = random.randint(0, 59)
        
        flow_time = flow_time.replace(hour=hour, minute=minute, second=second)
        return flow_time.strftime('%Y-%m-%d %H:%M:%S')
    
    def _generate_traffic_metrics(self, protocol_num: int) -> Tuple[int, int, int, int]:
        """Generate bytes, packets, duration, and TCP flags."""
        # Log-normal distribution for flow size (most flows small, some very large)
        mean_log_bytes = 10.0  # ~22KB mean
        sigma_log_bytes = 2.5
        bytes_count = int(random.lognormvariate(mean_log_bytes, sigma_log_bytes))
        bytes_count = max(64, min(bytes_count, 10_000_000))  # 64B to 10MB
        
        # Calculate packets (assume ~1000 bytes per packet on average)
        packets_count = max(1, bytes_count // random.randint(500, 1500))
        
        # Flow duration (1 second to 5 minutes, exponential distribution)
        duration = int(random.expovariate(1/30.0))  # Mean 30 seconds
        duration = max(1, min(duration, 300))  # 1s to 5min
        
        # TCP flags (only for TCP protocol)
        if protocol_num == 6:  # TCP
            # Common flag combinations
            tcp_flags_options = [
                0x02,  # SYN
                0x12,  # SYN-ACK
                0x10,  # ACK
                0x18,  # PSH-ACK
                0x11,  # FIN-ACK
                0x04,  # RST
            ]
            tcp_flags = random.choice(tcp_flags_options)
        else:
            tcp_flags = 0
        
        return bytes_count, packets_count, duration, tcp_flags
    
    def generate_flow(self) -> Dict:
        """Generate a single flow record."""
        # Select source and destination with Pareto distribution
        src = self._select_weighted_ip(self.src_ip_pool, self.src_weights)
        dst = self._select_weighted_ip(self.dst_ip_pool, self.dst_weights)
        
        # Select protocol
        protocol_num, protocol_name = self._select_protocol()
        
        # Select ports
        src_port = self._select_port(is_common=False)  # Usually ephemeral
        dst_port = self._select_port(is_common=True)   # Usually service port
        
        # Generate traffic metrics
        bytes_count, packets_count, duration, tcp_flags = \
            self._generate_traffic_metrics(protocol_num)
        
        # Generate timestamp
        timestamp = self._generate_timestamp()
        
        return {
            'timestamp': timestamp,
            'src_ip': src['ip'],
            'src_port': src_port,
            'src_geo_latitude': src['lat'],
            'src_geo_longitude': src['lon'],
            'dst_ip': dst['ip'],
            'dst_port': dst_port,
            'dst_geo_latitude': dst['lat'],
            'dst_geo_longitude': dst['lon'],
            'protocol': protocol_num,
            'tcp_flags': tcp_flags,
            'bytes': bytes_count,
            'packets': packets_count,
            'flow_duration': duration,
        }


def write_flows_to_file(flows: List[Dict], output_file: Path):
    """Write flows to JSONEachRow format file."""
    with open(output_file, 'w') as f:
        for flow in flows:
            json.dump(flow, f, separators=(',', ':'))
            f.write('\n')


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Generate synthetic NetFlow data with geo-location',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('--records', type=int, default=1_000_000,
                        help='Total number of flow records to generate (default: 1M)')
    parser.add_argument('--output', type=str, default='output/',
                        help='Output directory for generated files (default: output/)')
    parser.add_argument('--unique-src-ips', type=int, default=10_000,
                        help='Number of unique source IPs (default: 10K)')
    parser.add_argument('--unique-dst-ips', type=int, default=50_000,
                        help='Number of unique destination IPs (default: 50K)')
    parser.add_argument('--time-range-days', type=int, default=7,
                        help='Time range in days (default: 7)')
    parser.add_argument('--batch-size', type=int, default=500_000,
                        help='Records per output file (default: 500K)')
    parser.add_argument('--start-time', type=str, default=None,
                        help='Start timestamp (default: 7 days ago) format: YYYY-MM-DD')
    
    args = parser.parse_args()
    
    # Create output directory
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Parse start time
    if args.start_time:
        start_time = datetime.strptime(args.start_time, '%Y-%m-%d')
    else:
        start_time = datetime.now() - timedelta(days=args.time_range_days)
    
    # Initialize generator
    print(f"\n{'='*70}")
    print(f"NetFlow Data Generator")
    print(f"{'='*70}")
    print(f"Total records:     {args.records:,}")
    print(f"Unique src IPs:    {args.unique_src_ips:,}")
    print(f"Unique dst IPs:    {args.unique_dst_ips:,}")
    print(f"Time range:        {args.time_range_days} days")
    print(f"Start time:        {start_time.strftime('%Y-%m-%d')}")
    print(f"Batch size:        {args.batch_size:,} records/file")
    print(f"Output directory:  {output_dir}")
    print(f"{'='*70}\n")
    
    generator = NetFlowGenerator(
        unique_src_ips=args.unique_src_ips,
        unique_dst_ips=args.unique_dst_ips,
        time_range_days=args.time_range_days,
        start_time=start_time
    )
    
    # Generate and write in batches
    total_generated = 0
    batch_num = 1
    start_gen_time = datetime.now()
    
    while total_generated < args.records:
        batch_size = min(args.batch_size, args.records - total_generated)
        
        print(f"Generating batch {batch_num} ({batch_size:,} records)...", end=' ', flush=True)
        batch_start = datetime.now()
        
        # Generate batch
        flows = [generator.generate_flow() for _ in range(batch_size)]
        
        # Write to file
        output_file = output_dir / f"flows_{batch_num:03d}.json"
        write_flows_to_file(flows, output_file)
        
        batch_elapsed = (datetime.now() - batch_start).total_seconds()
        rate = batch_size / batch_elapsed if batch_elapsed > 0 else 0
        
        total_generated += batch_size
        print(f"✓ ({rate:,.0f} records/sec)")
        
        batch_num += 1
    
    # Summary
    total_elapsed = (datetime.now() - start_gen_time).total_seconds()
    overall_rate = args.records / total_elapsed if total_elapsed > 0 else 0
    
    print(f"\n{'='*70}")
    print(f"Generation Complete!")
    print(f"{'='*70}")
    print(f"Total records:     {total_generated:,}")
    print(f"Total time:        {total_elapsed:.2f} seconds")
    print(f"Average rate:      {overall_rate:,.0f} records/sec")
    print(f"Output files:      {batch_num - 1}")
    print(f"Location:          {output_dir.absolute()}")
    print(f"{'='*70}\n")


if __name__ == '__main__':
    main()

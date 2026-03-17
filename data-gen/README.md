# Data Generation

This directory contains scripts for generating synthetic NetFlow data with geo-location support for testing ClickHouse performance.

## Quick Start

```bash
# Quick test - 100K records (~3MB, ~30 seconds)
python generate_flows.py --records 100000 --unique-src-ips 1000 --unique-dst-ips 5000 --time-range-days 1

# Standard test - 10M records (~300MB, ~5 minutes)
python generate_flows.py --records 10000000 --unique-src-ips 10000 --unique-dst-ips 50000 --time-range-days 7

# Full scale - 250M records (~7.5GB, ~2 hours)
python generate_flows.py --records 250000000 --unique-src-ips 100000 --unique-dst-ips 500000 --time-range-days 60
```

## Features

- **Realistic data distribution**: Pareto distribution (80/20 rule) for IP traffic
- **Geographic coordinates**: 25 major world cities with random offsets
- **Protocol mix**: TCP 70%, UDP 25%, ICMP 5%
- **Common ports weighted**: HTTP/HTTPS, SSH, DNS, databases
- **Log-normal flow sizes**: Most flows small, some very large (realistic)
- **Temporal patterns**: Business hours peak (8AM-6PM weighted)
- **High performance**: 200K+ records/second generation rate
- **Batch output**: Split into multiple files for parallel ingestion

## Output Format

JSONEachRow format (one JSON object per line):
```json
{"timestamp": "2026-03-16 14:23:45", "src_ip": "10.45.123.201", "src_port": 52341, "src_geo_latitude": 40.7128, "src_geo_longitude": -74.0060, "dst_ip": "172.16.89.12", "dst_port": 443, "dst_geo_latitude": 51.5074, "dst_geo_longitude": -0.1278, "protocol": 6, "tcp_flags": 24, "bytes": 4096, "packets": 8, "flow_duration": 150}
```

## Files

- `generate_flows.py` - Main data generator
- `generate_flows_parallel.py` - Parallel version (faster for large datasets)
- `config.yaml` - Generation parameters
- `utils/` - Helper modules
- `output/` - Generated data files (gitignored)

## Data Characteristics

Generated NetFlow data includes:
- **Timestamp**: Distributed over configurable time range
- **Source/Destination IPs**: Pareto distribution (80/20 rule)
- **Ports**: Common ports weighted higher (80, 443, 22, etc.)
- **Protocols**: TCP 70%, UDP 25%, ICMP 5%
- **Bytes/Packets**: Log-normal distribution
- **Flow duration**: Realistic distribution

## Performance

Expected generation speed:
- Single-threaded: 100K-300K records/sec
- Parallel: 500K-1M records/sec

## Output Format

JSONEachRow format (one JSON object per line):
```json
{"timestamp": "2024-01-01 00:00:00", "src_ip": "192.168.1.1", "dst_ip": "10.0.0.1", "src_port": 54321, "dst_port": 80, "protocol": 6, "bytes": 1500, "packets": 10, "tcp_flags": 2, "flow_duration": 60}
```

## TODO

- [ ] Implement generate_flows.py
- [ ] Implement parallel generator
- [ ] Implement Prometheus converter
- [ ] Add validation script
- [ ] Add cardinality analysis tool

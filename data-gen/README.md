# Data Generation

This directory contains scripts for generating synthetic NetFlow data for testing ClickHouse performance.

## Quick Start

```bash
# Generate 1M records (~300MB)
python generate_flows.py --records 1000000 --output output/

# Generate full test dataset (2.5M records, ~750MB)
python generate_flows.py \
    --records 2500000 \
    --unique-src-ips 10000 \
    --unique-dst-ips 50000 \
    --output output/
```

## Files

- `generate_flows.py` - Main data generator
- `generate_flows_parallel.py` - Parallel version (faster for large datasets)
- `convert_to_prometheus.py` - Convert to Prometheus exposition format
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

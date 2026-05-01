# CICIDS2017 Dataset

## Overview

The **CICIDS2017** (Canadian Institute for Cybersecurity Intrusion Detection System) dataset is a widely-used benchmark dataset for network intrusion detection research. It contains realistic network traffic with both benign and malicious activities captured over 5 days in July 2017.

## Dataset Information

- **Source**: Canadian Institute for Cybersecurity (CIC), University of New Brunswick
- **Published**: 2017
- **Homepage**: https://www.unb.ca/cic/datasets/ids-2017.html
- **Size**: ~8GB compressed, ~16GB uncompressed
- **Format**: CSV files with labeled flows
- **Time Period**: 5 days (Monday-Friday, July 3-7, 2017)

## Dataset Features

The dataset includes:
- **Benign Traffic**: Normal user activities (browsing, email, file transfer, SSH, etc.)
- **Attack Traffic**: Various attack types including:
  - DoS/DDoS attacks
  - Port scanning
  - Brute force attacks
  - Web attacks (SQL injection, XSS)
  - Botnet traffic
  - Infiltration attempts

## Statistics

- **Total Flows**: ~2.8 million labeled flows
- **Benign Flows**: ~2.3 million
- **Attack Flows**: ~500,000
- **Network Protocols**: TCP, UDP, ICMP
- **Features per Flow**: 80+ features extracted from network packets

## Download Instructions

```bash
# Option 1: Download from official source
# Visit: https://www.unb.ca/cic/datasets/ids-2017.html
# Request access and download the CSV files

# Option 2: Download from Kaggle (requires Kaggle account)
# https://www.kaggle.com/datasets/cicdataset/cicids2017

# Place the CSV files in this directory:
# data-gen/cicids2017/
```

## Usage

### 1. Download the Dataset

Download the CICIDS2017 CSV files and place them in this directory.

Expected files:
```
Monday-WorkingHours.pcap_ISCX.csv
Tuesday-WorkingHours.pcap_ISCX.csv
Wednesday-WorkingHours.pcap_ISCX.csv
Thursday-WorkingHours.pcap_ISCX.csv
Friday-WorkingHours.pcap_ISCX.csv
```

### 2. Convert to Flow Log Format

```bash
# Convert CICIDS2017 CSV to our JSON flow format
python convert_cicids2017.py --input . --output output/ --sample 100000

# Options:
#   --input DIR     Directory containing CICIDS2017 CSV files (default: current dir)
#   --output DIR    Output directory for JSON files (default: output/)
#   --sample N      Sample N random flows (optional, processes all if not specified)
#   --add-geo       Add synthetic geographic coordinates (default: enabled)
```

### 3. Ingest into ClickHouse

```bash
# Use the standard ingestion script
cd ../../scripts/ingestion
./ingest_clickhouse.sh ../../data-gen/cicids2017/output
```

## Data Mapping

The conversion script maps CICIDS2017 fields to our flow log format:

| CICIDS2017 Field | Flow Log Field | Notes |
|------------------|----------------|-------|
| Timestamp | timestamp | Converted to YYYY-MM-DD HH:MM:SS format |
| Source IP | src_ip | Direct mapping |
| Source Port | src_port | Direct mapping |
| Destination IP | dst_ip | Direct mapping |
| Destination Port | dst_port | Direct mapping |
| Protocol | protocol | Mapped: TCP=6, UDP=17, ICMP=1 |
| Flow Duration | flow_duration | Converted to seconds |
| Total Fwd Packets + Total Backward Packets | packets | Sum of both directions |
| Total Length of Fwd Packets + Total Length of Bwd Packets | bytes | Sum of both directions |
| FIN Flag Count + SYN Flag Count + RST Flag Count + PSH Flag Count + ACK Flag Count + URG Flag Count | tcp_flags | Combined TCP flags |
| N/A | src_geo_latitude | Synthetic (based on IP range) |
| N/A | src_geo_longitude | Synthetic (based on IP range) |
| N/A | dst_geo_latitude | Synthetic (based on IP range) |
| N/A | dst_geo_longitude | Synthetic (based on IP range) |

## Advantages of CICIDS2017

✅ **Realistic Traffic**: Captured from real network environments
✅ **Well-Labeled**: Each flow is labeled (benign or specific attack type)
✅ **Diverse Attacks**: Covers multiple attack categories
✅ **Widely Used**: Benchmark dataset used in 500+ research papers
✅ **Rich Features**: 80+ extracted features for analysis
✅ **Public Access**: Freely available for research

## Citation

If you use this dataset, please cite:

```bibtex
@inproceedings{cicids2017,
  title={Toward generating a new intrusion detection dataset and intrusion traffic characterization},
  author={Sharafaldin, Iman and Lashkari, Arash Habibi and Ghorbani, Ali A},
  booktitle={ICISsp},
  pages={108--116},
  year={2018}
}
```

## License

The CICIDS2017 dataset is provided for research purposes. Please refer to the official website for license terms and conditions.

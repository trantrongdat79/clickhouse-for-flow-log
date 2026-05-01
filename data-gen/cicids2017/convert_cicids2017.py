#!/usr/bin/env python3
"""
Module: convert_cicids2017.py
Purpose: Convert CICIDS2017 dataset CSV files to flow log JSON format
Usage: python convert_cicids2017.py --input . --output output/ --sample 100000

Dependencies:
    - Python 3.8+
    - Standard library only

Features:
    - Converts CICIDS2017 CSV format to flow log JSON format
    - Maps network flow fields to standard format
    - Adds synthetic geographic coordinates
    - Optional sampling for testing
    - Handles multiple CSV files
"""

import argparse
import csv
import json
import random
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


# Major world cities with coordinates (lat, lon) for synthetic geo-distribution
MAJOR_LOCATIONS = [
    # North America
    (40.7128, -74.0060),   # New York
    (37.7749, -122.4194),  # San Francisco
    (34.0522, -118.2437),  # Los Angeles
    (41.8781, -87.6298),   # Chicago
    (43.6532, -79.3832),   # Toronto
    (49.2827, -123.1207),  # Vancouver

    # Europe
    (51.5074, -0.1278),    # London
    (48.8566, 2.3522),     # Paris
    (52.5200, 13.4050),    # Berlin

    # Asia Pacific
    (35.6762, 139.6503),   # Tokyo
    (1.3521, 103.8198),    # Singapore
    (-33.8688, 151.2093),  # Sydney
]


def _safe_float(value: object, default: float = 0.0) -> float:
    """Safely parse float-like values from CSV cells."""
    if value is None:
        return default
    text = str(value).strip()
    if not text:
        return default
    text = text.replace(",", "")
    try:
        return float(text)
    except (ValueError, TypeError):
        return default


def _safe_int(value: object, default: int = 0) -> int:
    """Safely parse int-like values from CSV cells."""
    try:
        return int(_safe_float(value, float(default)))
    except (ValueError, TypeError):
        return default


def _get_first(row: Dict[str, object], keys: List[str], default: object = 0) -> object:
    """Return the first matching value from a list of potential column names."""
    for key in keys:
        if key in row:
            return row[key]
    return default


class CICIDS2017Converter:
    """Convert CICIDS2017 dataset to flow log JSON format."""

    def __init__(self, add_geo: bool = True):
        self.add_geo = add_geo
        self.ip_geo_cache: Dict[str, Tuple[float, float]] = {}

    def _get_geo_for_ip(self, ip: str) -> Tuple[float, float]:
        """Get synthetic geographic coordinates for an IP address."""
        if ip in self.ip_geo_cache:
            return self.ip_geo_cache[ip]

        # Use IP hash to consistently assign locations
        location_idx = hash(ip) % len(MAJOR_LOCATIONS)
        lat, lon = MAJOR_LOCATIONS[location_idx]

        # Add small random offset for variety (within ~10km)
        lat += random.uniform(-0.1, 0.1)
        lon += random.uniform(-0.1, 0.1)

        geo = (round(lat, 4), round(lon, 4))
        self.ip_geo_cache[ip] = geo
        return geo

    def _map_protocol(self, protocol: int) -> int:
        """Map protocol number to standard values."""
        if protocol == 6:
            return 6
        if protocol == 17:
            return 17
        if protocol == 1:
            return 1
        return 6

    def _calculate_tcp_flags(self, row: Dict[str, object]) -> int:
        """Calculate TCP flags value from CICIDS2017 flag counts."""
        flags = 0
        if _safe_float(_get_first(row, ["FIN Flag Count"])) > 0:
            flags |= 1
        if _safe_float(_get_first(row, ["SYN Flag Count"])) > 0:
            flags |= 2
        if _safe_float(_get_first(row, ["RST Flag Count"])) > 0:
            flags |= 4
        if _safe_float(_get_first(row, ["PSH Flag Count"])) > 0:
            flags |= 8
        if _safe_float(_get_first(row, ["ACK Flag Count"])) > 0:
            flags |= 16
        if _safe_float(_get_first(row, ["URG Flag Count"])) > 0:
            flags |= 32
        return flags

    def _parse_timestamp(self, ts_value: object) -> str:
        """Parse and format timestamp from CICIDS2017."""
        ts_text = str(ts_value).strip()
        if not ts_text:
            return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        for fmt in [
            "%d/%m/%Y %H:%M:%S",
            "%d/%m/%Y %H:%M",
            "%d/%m/%Y %H:%M:%S.%f",
            "%Y-%m-%d %H:%M:%S",
        ]:
            try:
                return datetime.strptime(ts_text, fmt).strftime("%Y-%m-%d %H:%M:%S")
            except ValueError:
                continue

        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def convert_row(self, row: Dict[str, object]) -> Dict[str, object]:
        """Convert a single CICIDS2017 row to flow log format."""
        src_ip = str(_get_first(row, ["Source IP"], "0.0.0.0")).strip()
        dst_ip = str(_get_first(row, ["Destination IP"], "0.0.0.0")).strip()

        if self.add_geo:
            src_lat, src_lon = self._get_geo_for_ip(src_ip)
            dst_lat, dst_lon = self._get_geo_for_ip(dst_ip)
        else:
            src_lat = src_lon = dst_lat = dst_lon = 0.0

        timestamp = self._parse_timestamp(_get_first(row, ["Timestamp"], ""))
        src_port = _safe_int(_get_first(row, ["Source Port"], 0), 0)
        dst_port = _safe_int(_get_first(row, ["Destination Port"], 0), 0)
        protocol = self._map_protocol(_safe_int(_get_first(row, ["Protocol"], 6), 6))

        fwd_packets = _safe_float(_get_first(row, ["Total Fwd Packets"], 0.0), 0.0)
        bwd_packets = _safe_float(_get_first(row, ["Total Backward Packets"], 0.0), 0.0)
        packets = int(fwd_packets + bwd_packets)

        fwd_bytes = _safe_float(_get_first(row, ["Total Length of Fwd Packets"], 0.0), 0.0)
        bwd_bytes = _safe_float(_get_first(row, ["Total Length of Bwd Packets"], 0.0), 0.0)
        bytes_total = int(fwd_bytes + bwd_bytes)

        flow_duration_raw = _safe_float(_get_first(row, ["Flow Duration"], 0.0), 0.0)
        # CICIDS2017 flow duration is usually microseconds.
        flow_duration = int(flow_duration_raw / 1_000_000) if flow_duration_raw > 1_000_000 else int(flow_duration_raw)

        flow = {
            "timestamp": timestamp,
            "src_ip": src_ip,
            "src_port": src_port,
            "src_geo_latitude": src_lat,
            "src_geo_longitude": src_lon,
            "dst_ip": dst_ip,
            "dst_port": dst_port,
            "dst_geo_latitude": dst_lat,
            "dst_geo_longitude": dst_lon,
            "protocol": protocol,
            "tcp_flags": self._calculate_tcp_flags(row),
            "bytes": bytes_total,
            "packets": packets,
            "flow_duration": flow_duration,
        }
        return flow

    def _iter_rows(self, input_file: Path) -> Iterable[Dict[str, object]]:
        """Yield normalized rows from a CSV file."""
        with input_file.open("r", encoding="utf-8", errors="replace", newline="") as in_file:
            reader = csv.DictReader(in_file)
            if not reader.fieldnames:
                return

            reader.fieldnames = [name.strip() if name else "" for name in reader.fieldnames]

            for row in reader:
                normalized = {(k.strip() if k else ""): v for k, v in row.items()}
                yield normalized

    def convert_file(self, input_file: Path, output_file: Path, sample_size: Optional[int] = None) -> int:
        """Convert a CICIDS2017 CSV file to JSON format."""
        print(f"Processing: {input_file.name}")
        output_count = 0

        try:
            if sample_size and sample_size > 0:
                print(f"  Reservoir sampling up to {sample_size:,} rows...")
                sampled_rows: List[Dict[str, object]] = []

                for idx, row in enumerate(self._iter_rows(input_file), start=1):
                    if len(sampled_rows) < sample_size:
                        sampled_rows.append(row)
                    else:
                        replace_idx = random.randint(1, idx)
                        if replace_idx <= sample_size:
                            sampled_rows[replace_idx - 1] = row

                    if idx % 100000 == 0:
                        print(f"    Scanned {idx:,} rows...")

                print(f"  Converting {len(sampled_rows):,} sampled rows...")
                with output_file.open("w", encoding="utf-8") as out_file:
                    for row in sampled_rows:
                        flow = self.convert_row(row)
                        out_file.write(json.dumps(flow) + "\n")
                        output_count += 1
            else:
                print("  Converting all rows...")
                with output_file.open("w", encoding="utf-8") as out_file:
                    for idx, row in enumerate(self._iter_rows(input_file), start=1):
                        flow = self.convert_row(row)
                        out_file.write(json.dumps(flow) + "\n")
                        output_count += 1

                        if idx % 100000 == 0:
                            print(f"    Processed {idx:,} rows...")

            print(f"  Completed: {output_file.name} ({output_count:,} flows)")
            return output_count
        except Exception as error:
            print(f"  Error processing {input_file.name}: {error}")
            return 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert CICIDS2017 CSV files to flow log JSON format",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python convert_cicids2017.py
  python convert_cicids2017.py --sample 100000
  python convert_cicids2017.py --input ./cicids2017-csv --output ./output
  python convert_cicids2017.py --no-geo
        """,
    )

    parser.add_argument(
        "--input",
        "-i",
        type=str,
        default=".",
        help="Input directory containing CICIDS2017 CSV files (default: current directory)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default="output",
        help="Output directory for JSON files (default: output/)",
    )
    parser.add_argument(
        "--sample",
        "-s",
        type=int,
        default=None,
        help="Sample N random flows from each file (default: process all)",
    )
    parser.add_argument(
        "--no-geo",
        action="store_true",
        help="Do not add synthetic geographic coordinates",
    )

    args = parser.parse_args()

    input_dir = Path(args.input)
    output_dir = Path(args.output)

    if not input_dir.exists():
        print(f"ERROR: Input directory not found: {input_dir}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    csv_files = sorted(input_dir.glob("*.csv"))
    if not csv_files:
        print(f"ERROR: No CSV files found in {input_dir}")
        sys.exit(1)

    print(f"Found {len(csv_files)} CSV file(s)")
    print(f"Output directory: {output_dir.absolute()}")
    if args.sample and args.sample > 0:
        print(f"Sampling: {args.sample:,} flows per file")
    print()

    converter = CICIDS2017Converter(add_geo=not args.no_geo)
    total_flows = 0

    for idx, csv_file in enumerate(csv_files, start=1):
        print(f"[{idx}/{len(csv_files)}] {csv_file.name}")
        output_file = output_dir / f"flows_{csv_file.stem}.json"
        converted = converter.convert_file(csv_file, output_file, args.sample)
        total_flows += converted
        print()

    print("=" * 60)
    print("Conversion completed!")
    print(f"  Total flows: {total_flows:,}")
    print(f"  Output files: {len(csv_files)}")
    print(f"  Output directory: {output_dir.absolute()}")
    print("=" * 60)


if __name__ == "__main__":
    main()

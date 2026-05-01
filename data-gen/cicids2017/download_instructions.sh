#!/bin/bash
# 
# CICIDS2017 Dataset Download Helper
# 
# This script provides instructions for downloading the CICIDS2017 dataset.
# The dataset is not automatically downloadable due to access restrictions.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "CICIDS2017 Dataset Download Instructions"
echo "============================================================"
echo ""
echo "The CICIDS2017 dataset is available from multiple sources:"
echo ""
echo "OPTION 1: Official Source (University of New Brunswick)"
echo "  1. Visit: https://www.unb.ca/cic/datasets/ids-2017.html"
echo "  2. Request access (if required)"
echo "  3. Download the CSV files"
echo "  4. Extract to: ${SCRIPT_DIR}/"
echo ""
echo "OPTION 2: Kaggle (Requires Kaggle account)"
echo "  1. Visit: https://www.kaggle.com/datasets/cicdataset/cicids2017"
echo "  2. Click 'Download' button"
echo "  3. Extract to: ${SCRIPT_DIR}/"
echo ""
echo "OPTION 3: AWS Open Data (if available)"
echo "  Check: https://registry.opendata.aws/"
echo ""
echo "Expected CSV files after download:"
echo "  - Monday-WorkingHours.pcap_ISCX.csv"
echo "  - Tuesday-WorkingHours.pcap_ISCX.csv"
echo "  - Wednesday-WorkingHours.pcap_ISCX.csv"
echo "  - Thursday-WorkingHours.pcap_ISCX.csv"
echo "  - Friday-WorkingHours.pcap_ISCX.csv"
echo ""
echo "============================================================"
echo "After downloading, convert the dataset with:"
echo "  cd ${SCRIPT_DIR}"
echo "  python convert_cicids2017.py --sample 100000"
echo "============================================================"

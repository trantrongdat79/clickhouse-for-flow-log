# This is where the user store his ideas
## Measurement Strategy:
**Tier 1**: Fair Comparison (both systems attempt)
- Ingest 1% of data (750MB) into both
- Run simple time-range queries
- Document: ClickHouse 10-30x faster

**Tier 2**: Stress Test (Prometheus struggles)

- Ingest 10% (7.5GB) into ClickHouse
- Ingest 1% (750MB) into Prometheus (it can't handle more)
- Document: "Prometheus limited to 1/10th dataset due to cardinality"

**Tier 3**: ClickHouse-Only (Prometheus impossible)
- Full 75GB dataset
- High-cardinality queries
- Document: "Query not possible in Prometheus (reason: architectural constraints)"

## 
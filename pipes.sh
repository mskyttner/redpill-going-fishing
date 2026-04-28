#!/usr/bin/env bash
# pipes.sh — collect ps metrics into DuckLake, then render CPU sparklines
#
# Usage: ./pipes.sh [cycles] [interval_seconds]
#   cycles   — number of ingest passes (default: 6)
#   interval — seconds between passes (default: 5)
#
# Requires versitygw running and DuckLake catalog initialised.
# Extensions are loaded from .duckdbrc; S3 secret points to 127.0.0.1:9000.

set -euo pipefail

CYCLES="${1:-6}"
INTERVAL="${2:-5}"
SESSION_DB="data/session.db"

# Step 1+2: typed producer → transport bridge, repeated CYCLES times
printf 'Ingesting %s cycles (%ss apart)...\n' "$CYCLES" "$INTERVAL" >&2
for i in $(seq 1 "$CYCLES"); do
    printf '  cycle %s/%s\r' "$i" "$CYCLES" >&2
    duckdb --init .duckdbrc :memory: < ps_arrow.sql 2>/dev/null \
      | duckdb --init .duckdbrc "$SESSION_DB" \
          -c "LOAD arrow;
              SET ducklake_default_data_inlining_row_limit = 10000;
              ATTACH IF NOT EXISTS 'ducklake:data/catalog.db' AS lake (
                  DATA_PATH 's3://iot-lake/data/'
              );
              CREATE TABLE IF NOT EXISTS lake.events (
                  ts TIMESTAMPTZ, pid INTEGER, cpu DOUBLE,
                  mem DOUBLE, rss INTEGER, comm VARCHAR
              );
              INSERT INTO lake.events SELECT * FROM read_arrow('cat - |');" \
          2>/dev/null
    [[ "$i" -lt "$CYCLES" ]] && sleep "$INTERVAL"
done
printf '\n' >&2

# Step 3: lake consumer — CPU sparklines for top 20 processes
duckdb --init .duckdbrc :memory: < sparkline.sql 2>/dev/null

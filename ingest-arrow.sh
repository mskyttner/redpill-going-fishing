#!/usr/bin/env bash
# Two-DuckDB Arrow IPC pipe: ring buffer drain → typed Arrow IPC → DuckLake.
# Both sides use --init .duckdbrc (extensions + secret already loaded).
# .mode trash in .duckdbrc keeps the producer's stdout clean for the Arrow stream.
set -euo pipefail

DB="${1:-data/session.db}"
RINGBUFFER_URL="${RINGBUFFER_URL:-http://localhost:9001}"
DUCKLAKE_CATALOG="${DUCKLAKE_CATALOG:-data/catalog.db}"
DUCKLAKE_DATA_PATH="${DUCKLAKE_DATA_PATH:-s3://iot-lake/data/}"

echo "Starting Arrow IPC ingestion loop → $DB (Ctrl-C to stop)"
while true; do
    DRAIN_SQL="COPY (
        SELECT NOW() AS ts, pid, cpu, mem, rss, comm FROM read_csv(
            'curl -sf ${RINGBUFFER_URL}/drain |',
            header  = true,
            columns = {pid:'INTEGER', cpu:'DOUBLE', mem:'DOUBLE', rss:'INTEGER', comm:'VARCHAR'}
        )
    ) TO '/dev/stdout' (FORMAT ARROW);"

    duckdb --init .duckdbrc :memory: 2>/dev/null -c "$DRAIN_SQL" \
    | duckdb --init .duckdbrc "$DB" -c "
        ATTACH IF NOT EXISTS 'ducklake:${DUCKLAKE_CATALOG}' AS lake (
            DATA_PATH '${DUCKLAKE_DATA_PATH}'
        );
        INSERT INTO lake.events SELECT * FROM read_arrow('/dev/stdin');"
    sleep "${INGEST_INTERVAL:-5}"
done

#!/usr/bin/env bash
# Reads from ring buffer (:9001/drain) every 5 seconds and appends to DuckLake.
set -euo pipefail

DB="${1:-data/session.db}"
RINGBUFFER_URL="${RINGBUFFER_URL:-http://localhost:9001}"
DUCKLAKE_CATALOG="${DUCKLAKE_CATALOG:-data/catalog.db}"
DUCKLAKE_DATA_PATH="${DUCKLAKE_DATA_PATH:-s3://iot-lake/data/}"

echo "Starting ingestion loop → $DB (Ctrl-C to stop)"
while true; do
    duckdb --init .duckdbrc "$DB" <<SQL
        SET ducklake_default_data_inlining_row_limit = 10000;
        ATTACH IF NOT EXISTS 'ducklake:${DUCKLAKE_CATALOG}' AS lake (
            DATA_PATH '${DUCKLAKE_DATA_PATH}'
        );
        CREATE TABLE IF NOT EXISTS lake.events (
            ts   TIMESTAMPTZ,
            pid  INTEGER,
            cpu  DOUBLE,
            mem  DOUBLE,
            rss  INTEGER,
            comm VARCHAR
        );
        INSERT INTO lake.events
        SELECT NOW(), pid, cpu, mem, rss, comm FROM read_csv(
            'curl -sf ${RINGBUFFER_URL}/drain |',
            header  = true,
            columns = {
                pid:  'INTEGER',
                cpu:  'DOUBLE',
                mem:  'DOUBLE',
                rss:  'INTEGER',
                comm: 'VARCHAR'
            }
        );
SQL
    sleep "${INGEST_INTERVAL:-5}"
done

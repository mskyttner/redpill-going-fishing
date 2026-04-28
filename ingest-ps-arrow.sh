#!/usr/bin/env bash
set -euo pipefail

DB="${1:-data/session.db}"
DUCKLAKE_CATALOG="${DUCKLAKE_CATALOG:-data/catalog.db}"
DUCKLAKE_DATA_PATH="${DUCKLAKE_DATA_PATH:-s3://iot-lake/data/}"

duckdb --init .duckdbrc :memory: < ps_arrow.sql 2>/dev/null \
  | duckdb --init .duckdbrc "$DB" \
    -c "LOAD arrow;
        SET ducklake_default_data_inlining_row_limit = 10000;
        ATTACH IF NOT EXISTS 'ducklake:${DUCKLAKE_CATALOG}' AS lake (
            DATA_PATH '${DUCKLAKE_DATA_PATH}'
        );
        CREATE TABLE IF NOT EXISTS lake.events (
            ts TIMESTAMPTZ, pid INTEGER, cpu DOUBLE,
            mem DOUBLE, rss INTEGER, comm VARCHAR
        );
        INSERT INTO lake.events SELECT * FROM read_arrow('cat - |');"

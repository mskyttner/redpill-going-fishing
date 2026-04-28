#!/usr/bin/env bash
# Compact the DuckLake: merge small files, expire old snapshots, remove orphans.
# Run periodically (e.g. every 5 minutes) or on-demand via `make compact`.
set -euo pipefail

ONCE=false
DB="data/session.db"
for arg in "$@"; do
    case "$arg" in
        --once) ONCE=true ;;
        *) DB="$arg" ;;
    esac
done
DUCKLAKE_CATALOG="${DUCKLAKE_CATALOG:-data/catalog.db}"
DUCKLAKE_DATA_PATH="${DUCKLAKE_DATA_PATH:-s3://iot-lake/data/}"
COMPACT_INTERVAL="${COMPACT_INTERVAL:-300}"   # seconds between runs
TIME_TRAVEL_WINDOW="${TIME_TRAVEL_WINDOW:-1 hour}"

run_compact() {
    duckdb --init .duckdbrc :memory: <<SQL
        ATTACH IF NOT EXISTS 'ducklake:${DUCKLAKE_CATALOG}' AS lake (
            DATA_PATH '${DUCKLAKE_DATA_PATH}'
        );
        -- Flush any remaining inlined rows to Parquet before merging
        CALL ducklake_flush_inlined_data('lake');
        -- Merge small adjacent Parquet files into larger ones
        CALL ducklake_merge_adjacent_files('lake', 'events');
        -- Expire snapshots older than the time-travel window
        CALL ducklake_expire_snapshots('lake',
            older_than => NOW() - INTERVAL '${TIME_TRAVEL_WINDOW}');
        -- Delete Parquet files no longer referenced by any snapshot
        CALL ducklake_cleanup_old_files('lake',
            older_than => NOW() - INTERVAL '${TIME_TRAVEL_WINDOW}');
SQL
}

if [ "$ONCE" = true ]; then
    run_compact
else
    echo "Compaction loop: every ${COMPACT_INTERVAL}s, keeping ${TIME_TRAVEL_WINDOW} of history"
    while true; do
        run_compact
        sleep "$COMPACT_INTERVAL"
    done
fi

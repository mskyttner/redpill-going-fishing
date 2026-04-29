#!/usr/bin/env bash
# ingest-rest.sh — ingest ps metrics into DuckLake via the pequod REST API
#
# Usage: ./ingest-rest.sh [cycles] [interval_seconds]
#
# Reads the ring buffer drain via shellfs read_text (single HTTP pass — no
# double-read / double-drain problem), parses CSV in SQL, and inserts into
# DuckLake via POST /duckdb/execute. No local DuckDB process; pequod is the
# sole owner of catalog.db so there are no file lock conflicts.
#
# INSERT INTO ... WITH ... SELECT routes to ExecMain (write path) because the
# statement starts with INSERT, not WITH.
#
# Requires: pequod healthy at PEQUOD_URL with an admin key in PEQUOD_API_KEY.
#           RINGBUFFER_URL must be reachable from inside the pequod container.

set -euo pipefail

CYCLES="${1:-6}"
INTERVAL="${2:-5}"
PEQUOD_URL="${PEQUOD_URL:-http://localhost:8099}"
PEQUOD_API_KEY="${PEQUOD_API_KEY:-b9nnaGIqBz1BYbwDsLXQ0iterJkz8tyTn5bvwlV5rWQ}"
RINGBUFFER_URL="${RINGBUFFER_URL:-http://ringbuffer:9001}"

read -r -d '' SQL_TEMPLATE << 'SQLEOF'
INSERT INTO lake.events
WITH raw AS (
    SELECT unnest(string_split(content, E'\n')) AS line
    FROM read_text('curl -sf __RINGBUFFER_URL__/drain |')
),
fields AS (
    SELECT string_split(trim(line), ',') AS f
    FROM raw
    WHERE trim(line) != '' AND line NOT LIKE 'pid%'
)
SELECT NOW(), f[1]::INTEGER, f[2]::DOUBLE, f[3]::DOUBLE, f[4]::INTEGER, f[5]
FROM fields WHERE len(f) >= 5
SQLEOF

SQL="${SQL_TEMPLATE//__RINGBUFFER_URL__/$RINGBUFFER_URL}"

printf 'Ingesting %s cycles via REST (%ss apart)...\n' "$CYCLES" "$INTERVAL" >&2

for i in $(seq 1 "$CYCLES"); do
    printf '  cycle %s/%s\r' "$i" "$CYCLES" >&2
    RESULT=$(curl -sf "${PEQUOD_URL}/duckdb/execute" \
        -H "X-API-Key: ${PEQUOD_API_KEY}" \
        --data-binary "$SQL" 2>&1) || {
        printf '\ncycle %s failed: %s\n' "$i" "$RESULT" >&2
        exit 1
    }
    printf '  cycle %s/%s — %s\n' "$i" "$CYCLES" "$RESULT" >&2
    [[ "$i" -lt "$CYCLES" ]] && sleep "$INTERVAL"
done

printf '\nDone.\n' >&2

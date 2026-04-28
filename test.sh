#!/usr/bin/env bash
# End-to-end test for the streaming DuckLake demo.
# Starts VersityGW + ring buffer, runs two ingestion cycles, asserts data landed.
set -euo pipefail

cd "$(dirname "$0")"

PORT_VGW=19099
PORT_RB=19001
DATA_DIR="$(mktemp -d /tmp/fishing-test-XXXXXX)"
CATALOG="$DATA_DIR/catalog.db"
DB="$DATA_DIR/session.db"
PIDS=()

# Patch VGW port into a temp copy of .duckdbrc for this test run
RC="$DATA_DIR/.duckdbrc"
sed "s/127\.0\.0\.1:9000/127.0.0.1:$PORT_VGW/" .duckdbrc > "$RC"

DQ()  { duckdb --init "$RC" "$DB" "$@"; }
DQM() { duckdb --init "$RC" :memory: "$@"; }   # memory session, no lake attach

pass()   { echo "  ✓ $*"; }
fail()   { echo "  ✗ $*" >&2; exit 1; }
header() { echo; echo "── $* ──"; }

cleanup() {
    for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
    mc alias remove test-vgw 2>/dev/null || true
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# ── 1. prerequisites ──────────────────────────────────────────────────────────
header "Prerequisites"
command -v versitygw >/dev/null || fail "versitygw not found"
command -v duckdb    >/dev/null || fail "duckdb not found"
command -v mc        >/dev/null || fail "mc (MinIO client) not found"
command -v curl      >/dev/null || fail "curl not found"
[[ -f bin/ringbuffer ]] || go build -o bin/ringbuffer ./ringbuffer/...
pass "all tools present"

# ── 2. VersityGW ──────────────────────────────────────────────────────────────
header "VersityGW on :$PORT_VGW"
mkdir -p "$DATA_DIR/s3" "$DATA_DIR/iam"
ROOT_ACCESS_KEY=demo ROOT_SECRET_KEY=demoSecret \
    versitygw --port ":$PORT_VGW" --iam-dir "$DATA_DIR/iam" posix "$DATA_DIR/s3" \
    2>/dev/null &
PIDS+=($!)
sleep 1

mc alias set test-vgw "http://localhost:$PORT_VGW" demo demoSecret --api S3v4 2>/dev/null
mc mb test-vgw/iot-lake 2>/dev/null
pass "VersityGW running, bucket created"

# ── 3. DuckLake setup ─────────────────────────────────────────────────────────
header "DuckLake setup"
DQ <<SQL
ATTACH 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/');
CREATE TABLE IF NOT EXISTS lake.events (
    ts   TIMESTAMPTZ,
    pid  INTEGER,
    cpu  DOUBLE,
    mem  DOUBLE,
    rss  INTEGER,
    comm VARCHAR
);
SQL
pass "catalog and events table created"

# ── 4. Ring buffer ────────────────────────────────────────────────────────────
header "Ring buffer on :$PORT_RB"
{
    echo "pid,cpu,mem,rss,comm"
    while true; do
        ps -eo pid,pcpu,pmem,rss,comm --no-headers \
            | awk '{printf "%s,%.1f,%.1f,%s,%s\n",$1,$2,$3,$4,$5}'
        sleep 1
    done
} | ./bin/ringbuffer --addr ":$PORT_RB" 2>/dev/null &
PIDS+=($!)
sleep 2

BUFFERED=$(curl -sf "http://localhost:$PORT_RB/health" | grep -o '"buffered":[0-9]*' | cut -d: -f2)
[[ "${BUFFERED:-0}" -gt 0 ]] || fail "ring buffer empty after 2s"
pass "ring buffer has $BUFFERED records"

# ── 5. Ingestion — CSV path ───────────────────────────────────────────────────
header "Ingestion (CSV via shellfs)"
DQ <<SQL
ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/');
INSERT INTO lake.events
SELECT NOW(), pid, cpu, mem, rss, comm FROM read_csv(
    'curl -sf http://localhost:$PORT_RB/drain |',
    header  = true,
    columns = {pid:'INTEGER', cpu:'DOUBLE', mem:'DOUBLE', rss:'INTEGER', comm:'VARCHAR'}
);
SQL

COUNT=$(DQ -c "ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/'); SELECT COUNT(*)::INTEGER FROM lake.events;" \
    | grep -Eo '[0-9]+' | tail -1)
[[ "${COUNT:-0}" -gt 0 ]] || fail "no rows after CSV ingest"
pass "CSV ingest: $COUNT rows in lake"

# ── 6. Ingestion — Arrow IPC pipe ─────────────────────────────────────────────
header "Ingestion (Arrow IPC pipe)"
sleep 2

ARROW_SQL="COPY (
    SELECT NOW() AS ts, pid, cpu, mem, rss, comm FROM read_csv(
        'curl -sf http://localhost:$PORT_RB/drain |',
        header  = true,
        columns = {pid:'INTEGER', cpu:'DOUBLE', mem:'DOUBLE', rss:'INTEGER', comm:'VARCHAR'}
    )
) TO '/dev/stdout' (FORMAT ARROW);"

duckdb --init "$RC" :memory: 2>/dev/null -c "$ARROW_SQL" \
| DQ -c "
    ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/');
    INSERT INTO lake.events SELECT * FROM read_arrow('/dev/stdin');"

COUNT2=$(DQ -c "ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/'); SELECT COUNT(*)::INTEGER FROM lake.events;" \
    | grep -Eo '[0-9]+' | tail -1)
[[ "${COUNT2:-0}" -gt "${COUNT:-0}" ]] || fail "Arrow ingest added no rows (before=$COUNT after=$COUNT2)"
pass "Arrow IPC ingest: $COUNT2 rows total (+$((COUNT2 - COUNT)) new)"

# ── 7. Type assertions ────────────────────────────────────────────────────────
header "Type assertions"
TYPES=$(DQ -c "ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/');
    SELECT typeof(pid), typeof(cpu), typeof(rss), typeof(comm) FROM lake.events LIMIT 1;")
echo "$TYPES" | grep -q "INTEGER" || fail "pid/rss not INTEGER"
echo "$TYPES" | grep -q "DOUBLE"  || fail "cpu/mem not DOUBLE"
echo "$TYPES" | grep -q "VARCHAR" || fail "comm not VARCHAR"
pass "types correct: INTEGER, DOUBLE, VARCHAR"

# ── 8. Time travel ────────────────────────────────────────────────────────────
header "Time travel"
TS_BEFORE=$(date -u +"%Y-%m-%d %H:%M:%S+00")
sleep 1
DQ <<SQL
ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/');
INSERT INTO lake.events VALUES (NOW(), 99999, 99.9, 99.9, 999999, 'time-travel-marker');
SQL

MARKER_BEFORE=$(DQ -c "ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/');
    SELECT COUNT(*)::INTEGER FROM lake.events
    AT (timestamp => '$TS_BEFORE')
    WHERE comm = 'time-travel-marker';" | grep -Eo '[0-9]+' | tail -1)
[[ "${MARKER_BEFORE:-1}" -eq 0 ]] || fail "marker visible before its insert (snapshot isolation broken)"
pass "marker not visible at $TS_BEFORE"

MARKER_NOW=$(DQ -c "ATTACH IF NOT EXISTS 'ducklake:$CATALOG' AS lake (DATA_PATH 's3://iot-lake/data/');
    SELECT COUNT(*)::INTEGER FROM lake.events WHERE comm = 'time-travel-marker';" \
    | grep -Eo '[0-9]+' | tail -1)
[[ "${MARKER_NOW:-0}" -gt 0 ]] || fail "marker missing in current snapshot"
pass "marker visible in current snapshot"

# ── 9. Parquet files in VersityGW ─────────────────────────────────────────────
header "Parquet files in VersityGW"
PARQUET_COUNT=$(mc ls "test-vgw/iot-lake/data/" --recursive 2>/dev/null | grep -c "\.parquet" || true)
[[ "${PARQUET_COUNT:-0}" -gt 0 ]] || fail "no Parquet files in VersityGW"
pass "$PARQUET_COUNT Parquet file(s) in s3://iot-lake/data/"

echo
echo "All tests passed."

-- pequod-init.sql — runs at container startup via DUCKDB_INIT_FILE
-- Executed by the Go DuckDB driver (DuckDB 1.5.2): plain SQL only, no dot-commands.
--
-- pequod is the sole owner of catalog.db — all reads AND writes go through
-- this single connection, so there is no lock conflict with external writers.
--
-- Ingest via REST:
--   POST /duckdb/execute   (admin key, requires execute permission)
--   {"sql": "INSERT INTO lake.events SELECT NOW(), pid, cpu, mem, rss, comm
--            FROM read_csv('curl -sf http://ringbuffer:9001/drain |', header=true,
--            columns={pid:'INTEGER',cpu:'DOUBLE',mem:'DOUBLE',rss:'INTEGER',comm:'VARCHAR'})"}
--
-- shellfs lets the server-side DuckDB run shell commands, so the curl to the
-- ring buffer runs inside the container on the compose network — no port mapping needed.

LOAD httpfs;
LOAD ducklake;
LOAD shellfs;

CREATE OR REPLACE SECRET versity_s3 (
    TYPE      S3,
    KEY_ID    'demo',
    SECRET    'demoSecret',
    ENDPOINT  'versitygw:9000',
    URL_STYLE 'path',
    USE_SSL   false,
    REGION    'us-east-1'
);

-- Read-write attach: pequod is the only writer, no external lock conflict.
ATTACH 'ducklake:/data/catalog.db' AS lake (
    DATA_PATH 's3://iot-lake/data/'
);

-- Put lake in the search path so callers can write SELECT * FROM events
-- instead of SELECT * FROM lake.events.
SET search_path = 'lake,main';

-- pequod-init.sql — runs at container startup via DUCKDB_INIT_FILE
-- Executed by the Go DuckDB driver (DuckDB 1.5.2): plain SQL only, no dot-commands.
--
-- DuckLake catalog (catalog.db) is NOT attached here. A persistent ATTACH
-- holds a shared file lock that blocks the ingest writer's exclusive lock.
--
-- For REST API queries use read_parquet — lock-free, no catalog needed:
--   SELECT * FROM read_parquet('s3://iot-lake/data/**/*.parquet') LIMIT 20;
--
-- For time-travel use the DuckDB CLI directly (controls connection lifecycle):
--   ATTACH 'ducklake:data/catalog.db' AS lake (DATA_PATH 's3://iot-lake/data/');
--   SELECT * FROM lake.events AT (timestamp => NOW() - INTERVAL '5 minutes');
--   DETACH lake;

LOAD httpfs;
LOAD ducklake;

CREATE OR REPLACE SECRET versity_s3 (
    TYPE      S3,
    KEY_ID    'demo',
    SECRET    'demoSecret',
    ENDPOINT  'versitygw:9000',
    URL_STYLE 'path',
    USE_SSL   false,
    REGION    'us-east-1'
);

-- Attach DuckLake catalog read-write so lake.events is queryable by name.
-- Ingest holds an exclusive write lock only during its ~2s INSERT window per 5s
-- cycle; if a query collides, ingest retries (restart: on-failure covers this).
ATTACH 'ducklake:/data/catalog.db' AS lake (
    DATA_PATH 's3://iot-lake/data/',
    READ_ONLY true
);

-- Put lake in the search path so callers can write SELECT * FROM events
-- instead of SELECT * FROM lake.events.
SET search_path = 'lake,main';

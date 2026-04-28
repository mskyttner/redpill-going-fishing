-- Run once to initialise the DuckLake catalog and events table.
-- Requires VersityGW on :9000 and the iot-lake bucket to exist.
-- Usage: duckdb --init .duckdbrc data/session.db < setup.sql

ATTACH 'ducklake:data/catalog.db' AS lake (
    DATA_PATH 's3://iot-lake/data/'
);

CREATE TABLE IF NOT EXISTS lake.events (
    ts    TIMESTAMPTZ,
    pid   INTEGER,
    cpu   DOUBLE,
    mem   DOUBLE,
    rss   INTEGER,
    comm  VARCHAR
);

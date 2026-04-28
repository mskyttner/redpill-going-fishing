-- sparkline.sql — CPU timeseries sparklines for top 20 processes
-- Run against a live DuckLake:
--   duckdb --init .duckdbrc :memory: < sparkline.sql
-- .duckdbrc loads httpfs/ducklake/shellfs/arrow and the S3 secret.

INSTALL textplot FROM community;
LOAD textplot;

ATTACH IF NOT EXISTS 'ducklake:data/catalog.db' AS lake (
    DATA_PATH 's3://iot-lake/data/'
);
SET search_path = 'lake,main';

-- Bucket the last 5 minutes into 10-second intervals, show top 20 by avg CPU.
WITH bucketed AS (
    SELECT
        comm,
        time_bucket(INTERVAL '10 seconds', ts) AS bucket,
        AVG(cpu)                                AS avg_cpu
    FROM events
    WHERE ts >= NOW() - INTERVAL '5 minutes'
    GROUP BY comm, bucket
),
ranked AS (
    SELECT
        comm,
        AVG(avg_cpu)                                           AS overall_cpu,
        tp_sparkline(list(avg_cpu ORDER BY bucket),
                     width := 40,
                     mode  := 'absolute',
                     theme := 'utf8_blocks')                   AS cpu_trend
    FROM bucketed
    GROUP BY comm
    HAVING COUNT(*) >= 2
)
SELECT
    printf('%-20s', comm)          AS process,
    round(overall_cpu, 2)          AS avg_cpu,
    cpu_trend
FROM ranked
ORDER BY overall_cpu DESC
LIMIT 20;

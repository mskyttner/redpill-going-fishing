LOAD shellfs;

-- Each query of this view re-runs ps and stamps a fresh NOW() timestamp.
CREATE OR REPLACE VIEW ps_snapshot AS
WITH lines AS (
    SELECT unnest(string_split(content, E'\n')) AS line
    FROM read_text('ps -eo pid,pcpu,pmem,rss,comm --no-headers |')
),
fields AS (
    SELECT string_split_regex(trim(line), '\s+') AS f
    FROM lines
    WHERE trim(line) != ''
)
SELECT
    NOW()          AS ts,
    f[1]::INTEGER  AS pid,
    f[2]::DOUBLE   AS cpu,
    f[3]::DOUBLE   AS mem,
    f[4]::INTEGER  AS rss,
    f[5]           AS comm
FROM fields
WHERE len(f) >= 5;

SELECT * FROM ps_snapshot ORDER BY cpu DESC LIMIT 20;

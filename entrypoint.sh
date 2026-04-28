#!/bin/sh
# Generates /app/.duckdbrc from environment variables, then execs CMD.
# This lets compose services override VGW endpoint without rebuilding the image.
set -e

VGW_ENDPOINT="${VGW_ENDPOINT:-127.0.0.1:9000}"
VGW_ACCESS_KEY="${VGW_ACCESS_KEY:-demo}"
VGW_SECRET_KEY="${VGW_SECRET_KEY:-demoSecret}"

cat > /app/.duckdbrc << RCEOF
INSTALL httpfs   FROM core;
INSTALL ducklake FROM core;
INSTALL shellfs  FROM community;
INSTALL arrow    FROM community;

LOAD httpfs;
LOAD ducklake;
LOAD shellfs;
LOAD arrow;

.mode trash
CREATE OR REPLACE SECRET versity_s3 (
    TYPE      S3,
    KEY_ID    '${VGW_ACCESS_KEY}',
    SECRET    '${VGW_SECRET_KEY}',
    ENDPOINT  '${VGW_ENDPOINT}',
    URL_STYLE 'path',
    USE_SSL   false,
    REGION    'us-east-1'
);
.mode duckbox
RCEOF

exec "$@"

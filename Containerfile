# syntax=docker/dockerfile:1
# ── stage 1: build the Go ring buffer ─────────────────────────────────────────
FROM golang:1.26-bookworm AS builder

WORKDIR /build
COPY go.mod ./
RUN go mod download
COPY ringbuffer/ ./ringbuffer/
RUN CGO_ENABLED=0 go build -o bin/ringbuffer ./ringbuffer/...

# ── stage 2: runtime image ────────────────────────────────────────────────────
FROM ubuntu:24.04

ARG DUCKDB_VERSION=1.5.2

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        procps \
        gawk \
    && rm -rf /var/lib/apt/lists/*

# DuckDB CLI
RUN curl -fsSL \
        "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.gz" \
        | gunzip > /usr/local/bin/duckdb \
    && chmod +x /usr/local/bin/duckdb

# mc (MinIO client)
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
        -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

# Pre-install DuckDB extensions so containers start without needing internet
RUN duckdb :memory: \
    "INSTALL httpfs FROM core; \
     INSTALL ducklake FROM core; \
     INSTALL shellfs FROM community; \
     INSTALL arrow FROM community;"

# Ring buffer binary from builder stage
COPY --from=builder /build/bin/ringbuffer /usr/local/bin/ringbuffer

WORKDIR /app
COPY entrypoint.sh  ./
COPY setup.sql      ./
COPY ingest.sh      ./
COPY ingest-arrow.sh ./
COPY compact.sh     ./
COPY arc.toml       ./
RUN chmod +x entrypoint.sh ingest.sh ingest-arrow.sh compact.sh

# Data directory for DuckLake catalog, session db, and VersityGW storage
VOLUME ["/app/data"]

ENTRYPOINT ["/app/entrypoint.sh"]

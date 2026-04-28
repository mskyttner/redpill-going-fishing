# Time Series Analysis — DuckLake `events` via pequod REST/MCP API

**Source:** `lake.events` attached read-only in pequod (`data/catalog.db` → `s3://iot-lake/data/`)  
**Queried:** 2026-04-28 via `mcp__pequod__query`  
**Total rows:** 12 074 across 6 snapshots  
**Time range:** 15:41 UTC → 18:15 UTC (2h 34min)

---

## Dataset overview

| Metric | Value |
|--------|-------|
| Total rows | 12 074 |
| Distinct snapshots | 6 |
| Distinct processes | 6 (`sh`, `ringbuffer`, `ps`, `awk`, `curl`, `crun`) |
| Time range | 15:41:24 → 18:15:15 UTC |
| Gap in series | 15:43 → 18:10 (2h 27min — no ingest service running) |

Note: all data originates from `ps` running **inside the compose containers**, so only container-scoped processes are visible. CPU (`pcpu`) is 0.0 for all entries — the container processes are too lightweight to register a percentage point. RSS memory is the meaningful metric.

---

## Snapshot batch sizes

Each row in `lake.events` corresponds to one process entry from a single `ps` drain. The batch size per snapshot reveals the ring buffer state at drain time.

| Timestamp (UTC) | Rows in batch | Notes |
|-----------------|--------------|-------|
| 15:41:24 | 25 | Startup — only a handful of processes running |
| 15:43:30 | 627 | First full drain after stack settled |
| 18:10:39 | **10 000** | Ring buffer at full capacity — 2h 27min of accumulated output |
| 18:10:48 | 45 | Cleanup flush immediately after the full drain |
| 18:13:13 | 720 | Fresh cycle after compaction |
| 18:15:15 | 657 | Steady-state cycle |

**Key finding:** the 18:10:39 batch is exactly 10 000 rows — the ring buffer's hard capacity limit. During the 2.5-hour gap when no ingest service was running, the ring buffer silently overwrote old entries once full. Only the most recent 10 000 `ps` lines survived. This is the designed behaviour: the producer (`ps` loop) is never blocked, and the consumer (DuckDB ingest) picks up whatever fits when it next drains.

---

## Ringbuffer RSS memory over time

The Go ring buffer's resident set size grew steadily while accumulating unread data, then stabilised after the backlog was drained.

| Time bucket | Min RSS (MB) | Avg RSS (MB) | Peak RSS (MB) | Samples |
|-------------|-------------|-------------|--------------|---------|
| 15:40 (initial) | 5.65 | 6.34 | 6.41 | 130 |
| 18:10 (after 2.5h idle) | 9.02 | 9.19 | 10.11 | 2 152 |
| 18:15 (post-drain) | 9.38 | 9.38 | 9.42 | 131 |

**Growth:** ~3 MB over 2.5 hours of accumulation (6.3 → 9.2 MB). Consistent with the fixed-array design — strings are allocated once into the ring buffer's `[10 000]string` array and are not GC'd between cycles. The slight drop from 10.1 MB peak to 9.4 MB after draining reflects Go's GC reclaiming the overwritten string slots.

---

## Process RSS comparison (steady-state)

From the 18:13 snapshot (post-compaction, steady-state):

| Process | Avg RSS (MB) | Peak RSS (MB) | Role |
|---------|-------------|--------------|------|
| `ringbuffer` | 10.02 | 10.11 | Go ring buffer, holds 10 000 string slots |
| `ps` | 3.72 | 3.80 | Process metrics source, runs every 1s |
| `awk` | 3.44 | 3.55 | CSV formatter in the `ps` pipeline |
| `curl` | — | — | HTTP drain client (not in this snapshot) |
| `sh` | 1.41 | 1.84 | Shell script orchestrating the loop |

The ring buffer is the dominant memory consumer, as expected for a process that holds 10 000 string entries in memory at all times.

---

## Sampling regularity

| Minute bucket (UTC) | Snapshots | Total rows | Rows/snapshot |
|--------------------|-----------|------------|---------------|
| 15:41 | 1 | 25 | 25 |
| 15:43 | 1 | 627 | 627 |
| 18:10 | 2 | 10 045 | ~5 022 |
| 18:13 | 1 | 720 | 720 |
| 18:15 | 1 | 657 | 657 |

Steady-state cycles (18:13, 18:15) drain ~660–720 rows per 5-second interval, corresponding to ~660 container-visible processes per `ps` snapshot.

---

## Lock behaviour observed

Pequod's persistent `READ_ONLY` DuckLake ATTACH holds a shared file lock on `catalog.db`. This prevented the ingest service from acquiring the exclusive write lock needed to ATTACH for writing. Workaround used: stop pequod → run ingest cycles → run `make compact` → restart pequod. In production, this is resolved by the compose `restart: on-failure` policy on the ingest service, which retries when it loses the lock race.

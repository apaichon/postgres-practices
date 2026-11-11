# Module 5 lab notes: background writes, checkpoints, and WAL

These notes accompany [05-architecture.sql](05-architecture.sql), especially Lab 5B (background processes), Lab 5D.1 (page lifecycle), and Lab 5F (WAL). Examples target **PostgreSQL 18** on the ClaimSure primary.

Run a specific exercise from the repository root:

```bash
make lab5                 # list lab numbers
make lab5 LAB_NO=5B       # background process evidence
make lab5 LAB_NO=5D.1     # page lifecycle
make lab5 LAB_NO=5F       # WAL generation
make lab5 LAB_NO=all      # complete Module 5 lab
```

## What the three views tell you

| View | Question to investigate |
|---|---|
| `pg_stat_bgwriter` | Is background cleaning providing reusable buffers? |
| `pg_stat_checkpointer` | How frequently do checkpoints happen, and how much work do they perform? |
| `pg_stat_wal` | How much WAL does the workload generate? |

The background writer cleans dirty buffers so application backends can reuse them. Checkpoints establish recovery boundaries by writing and synchronizing data. WAL records protect changes before data-page writeback. See [background writer behavior](https://www.postgresql.org/docs/18/runtime-config-resource.html#RUNTIME-CONFIG-RESOURCE-BACKGROUND-WRITER) and [WAL/checkpoint behavior](https://www.postgresql.org/docs/18/wal-configuration.html).

## Read counters over an interval

These views contain cluster-wide totals since `stats_reset`. Compare two samples with unchanged reset timestamps. Statistics can lag; sample in autocommit mode, outside a long transaction. [Statistics documentation](https://www.postgresql.org/docs/18/monitoring-stats.html)

```sql
-- psql: display wide rows vertically.
\x on
SELECT * FROM pg_stat_bgwriter;
SELECT * FROM pg_stat_checkpointer;
SELECT * FROM pg_stat_wal;
\x off
```

For each counter:

```text
delta = value_after - value_before
rate  = delta / elapsed_seconds
```

Example: 600 MiB of additional WAL over 60 seconds means **10 MiB/s**. A lifetime total of 600 MiB alone cannot describe the current workload.

## `pg_stat_bgwriter`: background buffer cleaning

| Column | Meaning |
|---|---|
| `buffers_clean` | Buffers written by background writer |
| `maxwritten_clean` | Cleaning scans stopped at the write limit |
| `buffers_alloc` | Buffer allocations |

These count activity, not current buffer occupancy. [Column definitions](https://www.postgresql.org/docs/18/monitoring-stats.html#MONITORING-PG-STAT-BGWRITER-VIEW)

Interpret the changes together:

- Increasing `buffers_clean` shows background cleaning activity.
- Repeated increases in `maxwritten_clean` suggest investigating the per-round limit, `bgwriter_lru_maxpages`.
- Check whether application backends are also writing dirty buffers and experiencing latency before changing settings.
- More aggressive cleaning can increase total I/O: a repeatedly modified page can be written several times between checkpoints.

The background writer aims to supply reusable buffers according to demand; a small cleaning count alone does not demonstrate a failure. [Configuration and tradeoffs](https://www.postgresql.org/docs/18/runtime-config-resource.html#RUNTIME-CONFIG-RESOURCE-BACKGROUND-WRITER)

## `pg_stat_checkpointer`: checkpoint frequency and cost

| Column | Meaning |
|---|---|
| `num_timed` | Timeout-triggered checkpoints |
| `num_requested` | Requested checkpoints |
| `num_done` | Completed checkpoints |
| `buffers_written` | Shared buffers written |
| `slru_written` | SLRU buffers written |
| `write_time` | Cumulative write-phase milliseconds |
| `sync_time` | Cumulative synchronization-phase milliseconds |

Timed/requested counts include skipped checkpoints; `num_done` counts completed ones. `restartpoints_*` concerns recovery/standbys. [Column definitions](https://www.postgresql.org/docs/18/monitoring-stats.html#MONITORING-PG-STAT-CHECKPOINTER-VIEW)

Interpretation:

- Frequent requested checkpoints: inspect checkpoint logs. WAL growth approaching `max_wal_size` can trigger them, but manual `CHECKPOINT` commands can too.
- Large `write_time` does not automatically mean slow storage. Checkpoint writes are deliberately spread over time using `checkpoint_completion_target`.
- Increasing synchronization time alongside application latency is a reason to investigate storage.
- Frequent checkpoints can increase WAL volume: with `full_page_writes`, the first modification of a page after a checkpoint logs a full-page image.

These observations suggest where to investigate; they do not establish a universal tuning threshold. [Checkpoint behavior](https://www.postgresql.org/docs/18/wal-configuration.html)

## `pg_stat_wal`: WAL generation

| Column | Meaning |
|---|---|
| `wal_records` | WAL records generated |
| `wal_fpi` | Full-page images generated |
| `wal_bytes` | WAL bytes generated |
| `wal_buffers_full` | Writes caused by full WAL buffers |

These measure WAL generation and buffer pressure, not transaction counts. [Column definitions](https://www.postgresql.org/docs/18/monitoring-stats.html#MONITORING-PG-STAT-WAL-VIEW)

Calculate WAL bytes per second and compare with a representative workload baseline. Rapid increases in `wal_buffers_full` suggest investigating write bursts and WAL buffering. Increasing full-page images alongside frequent checkpoints may explain some additional WAL. Neither observation alone proves a bottleneck. [WAL behavior](https://www.postgresql.org/docs/18/wal-configuration.html)

## Exercise: capture before and after the lab

Use two connections to the same primary. Keep the observer connection open throughout the exercise; its temporary tables belong to that session.

In the **observer connection**, capture a baseline:

```sql
-- Run with autocommit enabled; do not wrap the exercise in BEGIN/COMMIT.
SELECT pg_stat_clear_snapshot();

DROP TABLE IF EXISTS pg_temp.m5_bg_before;
DROP TABLE IF EXISTS pg_temp.m5_cp_before;
DROP TABLE IF EXISTS pg_temp.m5_wal_before;

CREATE TEMP TABLE m5_bg_before AS
SELECT * FROM pg_stat_bgwriter;

CREATE TEMP TABLE m5_cp_before AS
SELECT * FROM pg_stat_checkpointer;

CREATE TEMP TABLE m5_wal_before AS
SELECT clock_timestamp() AS sampled_at, w.*
FROM pg_stat_wal AS w;
```

In the **workload connection**, run Lab 5F from [05-architecture.sql](05-architecture.sql). Alternatively, run the complete file from the repository root:

```bash
make sql-v3 LAB=05-architecture.sql
```

The complete file also performs the other exercises. Lab 5F commits 1,000 audit events and then deletes its own batch. The observer interval therefore includes cleanup WAL and any concurrent cluster activity; it will not match the narrower insert measurement printed by Lab 5F.

After the workload finishes, allow a few seconds for statistics reporting. In the **observer connection**, calculate differences:

```sql
SELECT pg_stat_clear_snapshot();

SELECT a.buffers_clean - b.buffers_clean AS buffers_clean_delta,
       a.maxwritten_clean - b.maxwritten_clean AS cleaning_limit_hits,
       a.buffers_alloc - b.buffers_alloc AS allocations_delta
FROM pg_stat_bgwriter AS a
CROSS JOIN m5_bg_before AS b
WHERE a.stats_reset IS NOT DISTINCT FROM b.stats_reset;

SELECT a.num_timed - b.num_timed AS timed_delta,
       a.num_requested - b.num_requested AS requested_delta,
       a.num_done - b.num_done AS completed_delta,
       a.buffers_written - b.buffers_written AS buffers_written_delta,
       a.write_time - b.write_time AS write_phase_ms,
       a.sync_time - b.sync_time AS sync_phase_ms
FROM pg_stat_checkpointer AS a
CROSS JOIN m5_cp_before AS b
WHERE a.stats_reset IS NOT DISTINCT FROM b.stats_reset;

WITH sample AS (
    SELECT clock_timestamp() AS sampled_at, w.*
    FROM pg_stat_wal AS w
)
SELECT round(extract(epoch FROM a.sampled_at - b.sampled_at), 2)
           AS elapsed_seconds,
       a.wal_records - b.wal_records AS records_delta,
       a.wal_fpi - b.wal_fpi AS full_page_images_delta,
       pg_size_pretty(a.wal_bytes - b.wal_bytes) AS wal_generated,
       round((a.wal_bytes - b.wal_bytes)
             / NULLIF(extract(epoch FROM a.sampled_at - b.sampled_at), 0), 2)
           AS wal_bytes_per_second,
       a.wal_buffers_full - b.wal_buffers_full AS full_buffer_writes
FROM sample AS a
CROSS JOIN m5_wal_before AS b
WHERE a.stats_reset IS NOT DISTINCT FROM b.stats_reset;
```

If a delta query returns no row, its reset timestamp changed. Capture a new baseline instead of comparing across the reset.

Record your observations:

| Observation | Interpretation to investigate |
|---|---|
| Positive WAL delta | The interval included WAL-generating work. |
| Zero completed checkpoints during a short exercise | The interval may not contain a completed checkpoint. |
| Repeated cleaning-limit hits | Check background cleaning demand and application latency. |
| Requested checkpoints and WAL generation both rise | Check logs for checkpoint triggers and workload changes. |
| Large checkpoint write-phase time | Check pacing before attributing it to slow storage. |

These are hypotheses for the exercise, not diagnoses of the running server. Do not force a checkpoint merely to make a counter change: that changes the workload you are observing.

## PostgreSQL 18: where to inspect WAL I/O timing

PostgreSQL 18 moved WAL I/O reporting to `pg_stat_io`. Older queries using `pg_stat_wal.wal_write`, `wal_sync`, `wal_write_time`, or `wal_sync_time` will not work. `track_wal_io_timing` now controls WAL timing in `pg_stat_io`. [PostgreSQL 18 changes](https://www.postgresql.org/docs/18/release-18.html)

```sql
SHOW track_wal_io_timing;

SELECT backend_type, writes, write_time, fsyncs, fsync_time
FROM pg_stat_io
WHERE object = 'wal'
ORDER BY backend_type;
```

Timing requires tracking; zero timing with tracking disabled is not evidence of instantaneous I/O. Compare intervals with consistent tracking settings. [I/O statistics](https://www.postgresql.org/docs/18/monitoring-stats.html#MONITORING-PG-STAT-IO-VIEW)

For your lab report, write the observation interval, counter differences, relevant workload, and evidence supporting each interpretation. For example: “During this 60-second sample, WAL increased by 600 MiB, or 10 MiB/s. The sample included the insert batch and cleanup; this is a cluster-wide measurement.”

\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 9: Monitoring and Troubleshooting ==='

CREATE SCHEMA IF NOT EXISTS lab_m9;
CREATE TABLE IF NOT EXISTS lab_m9.lock_demo (
    id integer PRIMARY KEY,
    note text NOT NULL
);
INSERT INTO lab_m9.lock_demo VALUES (1, 'ready')
ON CONFLICT (id) DO UPDATE SET note = EXCLUDED.note;

\echo '\n-- Lab 9A: connection and workload snapshot'
SELECT state, wait_event_type, wait_event, count(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state, wait_event_type, wait_event
ORDER BY sessions DESC;

SELECT pid, usename, application_name, state,
       clock_timestamp() - query_start AS query_age,
       clock_timestamp() - xact_start AS transaction_age,
       wait_event_type, wait_event,
       left(query, 120) AS query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
ORDER BY query_start NULLS LAST;

\echo '\n-- Lab 9B: slow SQL and cache efficiency'
SELECT EXISTS (SELECT FROM pg_extension WHERE extname = 'pg_stat_statements') AS has_pgss \gset
\if :has_pgss
SELECT calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows,
       shared_blks_hit,
       shared_blks_read,
       left(query, 120) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 15;
\else
\echo 'pg_stat_statements is not installed in this database.'
\endif

SELECT datname,
       blks_hit,
       blks_read,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_percent,
       temp_files,
       pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname = current_database();

\echo '\n-- Lab 9C: blocker -> blocked relationship'
SELECT blocked.pid AS blocked_pid,
       blocker.pid AS blocker_pid,
       clock_timestamp() - blocked.query_start AS blocked_for,
       blocked.wait_event_type,
       blocked.wait_event,
       left(blocked.query, 100) AS blocked_query,
       left(blocker.query, 100) AS blocker_query
FROM pg_stat_activity blocked
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
JOIN pg_stat_activity blocker ON blocker.pid = b.blocker_pid
ORDER BY blocked_for DESC;

\echo '\n-- Lab 9D: database, table, maintenance, WAL and replication health'
SELECT datname, numbackends, xact_commit, xact_rollback,
       deadlocks, conflicts, temp_files, pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname = current_database();

SELECT schemaname, relname, n_live_tup, n_dead_tup,
       last_autovacuum, last_autoanalyze,
       vacuum_count, autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;

SELECT archived_count, failed_count, last_archived_wal,
       last_archived_time, last_failed_wal, last_failed_time
FROM pg_stat_archiver;

SELECT application_name, state, sync_state, write_lag, flush_lag, replay_lag
FROM pg_stat_replication
ORDER BY application_name;

SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('log_min_duration_statement','log_lock_waits',
               'deadlock_timeout','track_io_timing','track_functions')
ORDER BY name;

\echo '\nUse 09-blocking-session-a.sql and 09-blocking-session-b.sql for the live lock exercise.'

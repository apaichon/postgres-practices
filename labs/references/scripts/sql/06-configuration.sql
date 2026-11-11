-- =============================================================================
-- Module 6: ClaimSure Evidence-Driven PostgreSQL Configuration Practice
-- Run: make lab-v3 LAB_NO=06
-- Requires: PostgreSQL 18, the ClaimSure primary, and the postgres lab role.
--
-- Decision pattern used in every practice:
--   symptom -> evidence -> parameter -> test value -> measurement -> keep/revert
--
-- The lab changes only the current session, current transaction, or lab_m6
-- objects. It does not run ALTER SYSTEM, restart PostgreSQL, or change a
-- production table. Replace the teaching inputs with representative workload
-- measurements before using any calculated value outside this lab.
-- =============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing on
\echo '=== Module 6: ClaimSure Configuration Decisions ==='
\conninfo

DO $$
BEGIN
    IF current_setting('server_version_num')::int < 180000 THEN
        RAISE EXCEPTION 'This lab targets PostgreSQL 18 or newer; server is %', version();
    END IF;
    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Run Module 6 on the ClaimSure primary, not a standby.';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'Run this configuration lab as the postgres lab superuser.';
    END IF;
END
$$;

CREATE SCHEMA IF NOT EXISTS lab_m6;

CREATE TABLE IF NOT EXISTS lab_m6.claim_report_workload AS
SELECT g AS claim_id,
       'CLM-LAB-' || lpad(g::text, 7, '0') AS claim_no,
       1 + (g % 100) AS tenant_id,
       (ARRAY['BKK', 'CNX', 'HKT', 'KKN'])[1 + (g % 4)] AS branch_code,
       (ARRAY['NEW', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'PAID', 'CLOSED'])
           [1 + (g % 6)] AS status,
       clock_timestamp() - ((g % 365) || ' days')::interval AS incident_at,
       (5000 + (g % 500000))::numeric(12,2) AS estimated_amount,
       1 + (g % 250) AS adjuster_id,
       jsonb_build_object(
           'loss_type', (ARRAY['collision', 'flood', 'fire', 'theft'])[1 + (g % 4)],
           'district', 'DISTRICT-' || lpad((g % 80)::text, 2, '0'),
           'note', repeat(md5(g::text), 3)
       ) AS claim_details
FROM generate_series(1, 100000) AS g
WITH DATA;
ANALYZE lab_m6.claim_report_workload;

\echo '\n-- Lab 6A: Read effective configuration before proposing a change'
SELECT name, setting, unit, context, source,
       min_val, max_val, pending_restart
FROM pg_settings
WHERE name IN (
    'archive_command', 'archive_mode',
    'max_connections', 'reserved_connections', 'superuser_reserved_connections',
    'shared_buffers', 'work_mem', 'hash_mem_multiplier',
    'maintenance_work_mem', 'effective_cache_size',
    'statement_timeout', 'lock_timeout',
    'fsync', 'full_page_writes', 'synchronous_commit', 'wal_level',
    'min_wal_size', 'max_wal_size',
    'checkpoint_timeout', 'checkpoint_completion_target',
    'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
    'log_min_duration_statement', 'log_temp_files', 'log_lock_waits'
)
ORDER BY category, name;

SELECT sourcefile, sourceline, name, setting, applied, error
FROM pg_file_settings
WHERE name IS NOT NULL
ORDER BY sourcefile, sourceline;

SELECT name, setting, source, pending_restart
FROM pg_settings
WHERE pending_restart
ORDER BY name;

-- Decision rule:
-- user/superuser context -> test in one transaction or session first
-- sighup context         -> edit controlled config, reload, verify
-- postmaster context     -> plan restart and rollback before changing

\echo '\n-- Which WAL settings can be assigned as a role default?'
SELECT name, setting, unit, context, source,
       CASE context
           WHEN 'user' THEN 'yes'
           WHEN 'superuser' THEN 'yes, when assigned by a superuser'
           ELSE 'no: use cluster configuration'
       END AS role_default
FROM pg_settings
WHERE name IN (
    'archive_command', 'archive_mode', 'checkpoint_timeout',
    'fsync', 'full_page_writes', 'max_wal_size', 'min_wal_size',
    'synchronous_commit', 'wal_level'
)
ORDER BY name;

-- ALTER ROLE stores a default for future login sessions. SET ROLE inside an
-- existing connection does not load that role's defaults. This transaction
-- demonstrates ClaimSure role defaults and then rolls back the catalog changes.
BEGIN;
ALTER ROLE claim_app IN DATABASE claimsure
    SET synchronous_commit = 'on';
ALTER ROLE adjuster_bkk IN DATABASE claimsure
    SET lock_timeout = '3s';
ALTER ROLE adjuster_bkk IN DATABASE claimsure
    SET statement_timeout = '15s';
ALTER ROLE internal_auditor IN DATABASE claimsure
    SET work_mem = '32MB';
ALTER ROLE internal_auditor IN DATABASE claimsure
    SET statement_timeout = '10min';

SELECT d.datname AS database_name,
       r.rolname AS role_name,
       s.setconfig AS pending_login_defaults
FROM pg_db_role_setting AS s
JOIN pg_database AS d ON d.oid = s.setdatabase
JOIN pg_roles AS r ON r.oid = s.setrole
WHERE d.datname = 'claimsure'
  AND r.rolname IN ('claim_app', 'adjuster_bkk', 'internal_auditor')
ORDER BY r.rolname;
ROLLBACK;

-- Production application and rollback pattern:
-- ALTER ROLE internal_auditor IN DATABASE claimsure SET work_mem = '32MB';
-- Reconnect as internal_auditor, then run: SHOW work_mem;
-- ALTER ROLE internal_auditor IN DATABASE claimsure RESET work_mem;
--
-- archive_command, archive_mode, checkpoint_timeout, fsync, full_page_writes,
-- max_wal_size, min_wal_size, and wal_level are cluster settings. Do not try
-- to assign them with ALTER ROLE. Use controlled cluster configuration and the
-- activation method reported by pg_settings.context.

\echo '\n-- Lab 6B: work_mem for the open-claim reserve report'
DROP TABLE IF EXISTS lab_m6.work_mem_results;
CREATE TABLE lab_m6.work_mem_results (
    test_label text NOT NULL,
    tested_work_mem text NOT NULL,
    run_no integer NOT NULL,
    sort_method text,
    sort_space_type text,
    sort_space_kb bigint,
    temp_read_blocks bigint,
    temp_written_blocks bigint,
    execution_ms numeric,
    measured_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION lab_m6.measure_open_claim_report_sort(
    p_label text,
    p_work_mem text,
    p_run_no integer
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    plan_json jsonb;
    sort_node jsonb;
BEGIN
    -- true means transaction-local. Each function call is one statement and
    -- restores the caller's original value when that statement ends.
    PERFORM set_config('work_mem', p_work_mem, true);
    PERFORM set_config('max_parallel_workers_per_gather', '0', true);

    EXECUTE $plan$
        EXPLAIN (ANALYZE, BUFFERS, SETTINGS, FORMAT JSON)
        SELECT claim_no, tenant_id, branch_code, status, incident_at,
               estimated_amount, adjuster_id, claim_details
        FROM lab_m6.claim_report_workload
        WHERE status IN ('NEW', 'UNDER_REVIEW', 'APPROVED')
        ORDER BY branch_code, status, estimated_amount DESC, claim_no
    $plan$ INTO plan_json;

    sort_node := plan_json->0->'Plan';

    INSERT INTO lab_m6.work_mem_results (
        test_label, tested_work_mem, run_no,
        sort_method, sort_space_type, sort_space_kb,
        temp_read_blocks, temp_written_blocks, execution_ms
    )
    VALUES (
        p_label,
        p_work_mem,
        p_run_no,
        sort_node->>'Sort Method',
        sort_node->>'Sort Space Type',
        COALESCE((sort_node->>'Sort Space Used')::bigint, 0),
        COALESCE((sort_node->>'Temp Read Blocks')::bigint, 0),
        COALESCE((sort_node->>'Temp Written Blocks')::bigint, 0),
        (plan_json->0->>'Execution Time')::numeric
    );
END
$$;

-- A ladder reveals the smallest tested value that avoids a spill. Three runs
-- reduce the chance that one noisy timing drives the decision.
SELECT lab_m6.measure_open_claim_report_sort(v.label, v.work_mem, r.run_no)
FROM (VALUES
    ('very_small', '64kB'),
    ('middle_test', '4MB'),
    ('candidate', '32MB')
) AS v(label, work_mem)
CROSS JOIN generate_series(1, 3) AS r(run_no);

SELECT test_label,
       tested_work_mem,
       count(*) AS runs,
       min(sort_space_type) AS sort_space_type,
       max(temp_written_blocks) AS max_temp_written_blocks,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY execution_ms)::numeric, 2)
           AS median_execution_ms,
       max(sort_space_kb) AS max_sort_space_kb
FROM lab_m6.work_mem_results
GROUP BY test_label, tested_work_mem
ORDER BY min(measured_at);

\echo '\n-- Claim reserve report memory budget: replace inputs with monitored peaks'
\set candidate_work_mem_mb 32
\set concurrent_claim_reports 4
\set memory_nodes_per_claim_report 2
\set processes_per_claim_report 1
\set claim_reporting_memory_budget_mb 512

SELECT :candidate_work_mem_mb AS candidate_work_mem_mb,
       :concurrent_claim_reports AS concurrent_claim_reports,
       :memory_nodes_per_claim_report AS operations_per_report,
       :processes_per_claim_report AS leader_plus_workers,
       :candidate_work_mem_mb * :concurrent_claim_reports
           * :memory_nodes_per_claim_report * :processes_per_claim_report
           AS estimated_peak_mb,
       :claim_reporting_memory_budget_mb AS budget_mb,
       (:candidate_work_mem_mb * :concurrent_claim_reports
           * :memory_nodes_per_claim_report * :processes_per_claim_report)
           <= :claim_reporting_memory_budget_mb AS fits_claim_reporting_budget;

-- Keep the smallest tested value that removes the spill and improves repeatable
-- latency while the concurrency estimate fits the workload memory budget.
-- Prefer SET LOCAL for the reserve report or a claim-reporting role default.
-- Revert if host memory pressure, swap, OOM risk, or claim API latency increases.
SHOW work_mem;
BEGIN;
SET LOCAL work_mem = '32MB';
SHOW work_mem;
ROLLBACK;
SHOW work_mem;

\echo '\n-- Lab 6C: claim intake, adjuster, and settlement connection capacity'
WITH connection_setting AS (
    SELECT setting::int AS max_connections
    FROM pg_settings WHERE name = 'max_connections'
), activity AS (
    SELECT count(*) FILTER (WHERE backend_type = 'client backend') AS clients,
           count(*) FILTER (WHERE backend_type = 'client backend'
                              AND state = 'active') AS active,
           count(*) FILTER (WHERE backend_type = 'client backend'
                              AND state = 'idle') AS idle,
           count(*) FILTER (WHERE backend_type = 'client backend'
                              AND state LIKE 'idle in transaction%') AS idle_in_xact,
           max(clock_timestamp() - xact_start)
               FILTER (WHERE state LIKE 'idle in transaction%') AS oldest_idle_xact
    FROM pg_stat_activity
)
SELECT c.max_connections, a.clients, a.active, a.idle, a.idle_in_xact,
       a.oldest_idle_xact,
       round(100.0 * a.clients / c.max_connections, 2) AS slots_used_percent
FROM connection_setting AS c
CROSS JOIN activity AS a;

SELECT pid, usename, application_name, state,
       wait_event_type, wait_event, xact_start,
       left(query, 100) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY state, xact_start NULLS LAST;

-- Set application_name in each client so the DBA can separate ClaimSure pools.
SELECT coalesce(nullif(application_name, ''), '(not set)') AS claim_workload,
       state,
       count(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY claim_workload, state
ORDER BY claim_workload, state;

\set measured_peak_claim_workers 20
\set dba_reserve 5
\set settlement_and_failover_headroom 5
SELECT :measured_peak_claim_workers AS measured_peak_claim_workers,
       :dba_reserve AS dba_reserve,
       :settlement_and_failover_headroom AS other_headroom,
       :measured_peak_claim_workers + :dba_reserve
           + :settlement_and_failover_headroom
           AS first_capacity_test;

-- Replace measured_peak_claim_workers with a sustained peak covering the claim
-- intake API and adjuster workbench. If slots are full while active sessions
-- remain low, inspect each client pool, leaked sessions, and idle transactions
-- before raising max_connections. Include settlement batch overlap in the test.

BEGIN;
SET LOCAL statement_timeout = '5s';
SET LOCAL lock_timeout = '1s';
SET LOCAL idle_in_transaction_session_timeout = '2min';
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('statement_timeout', 'lock_timeout',
               'idle_in_transaction_session_timeout')
ORDER BY name;
ROLLBACK;

-- Success: claim intake and approval meet their latency/error budgets, timeout
-- logs identify the cause, and retry behavior is safe. Revert or widen a timeout
-- if a valid settlement or reserve job is cancelled without reducing the wait.

\echo '\n-- Lab 6D: claim event WAL and checkpoints'
DROP TABLE IF EXISTS lab_m6.claim_event_wal_probe;
CREATE TABLE lab_m6.claim_event_wal_probe (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL,
    event_type text NOT NULL,
    event_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload jsonb NOT NULL
);

DROP TABLE IF EXISTS pg_temp.m6_checkpointer_before;
CREATE TEMP TABLE m6_checkpointer_before AS
SELECT clock_timestamp() AS sampled_at, c.*
FROM pg_stat_checkpointer AS c;

SELECT pg_current_wal_insert_lsn() AS m6_wal_start_lsn \gset
INSERT INTO lab_m6.claim_event_wal_probe (claim_no, event_type, payload)
SELECT 'CLM-WAL-' || lpad(g::text, 7, '0'),
       (ARRAY['CLAIM_RECEIVED', 'DOCUMENT_ATTACHED', 'REVIEW_ASSIGNED',
              'RESERVE_CHANGED', 'STATUS_CHANGED'])[1 + (g % 5)],
       jsonb_build_object(
           'tenant_id', 1 + (g % 100),
           'actor', 'claim-worker-' || (1 + (g % 40)),
           'correlation_id', md5(g::text),
           'audit_note', repeat(md5((g * 17)::text), 4)
       )
FROM generate_series(1, 5000) AS g;
SELECT pg_current_wal_insert_lsn() AS m6_wal_end_lsn \gset

SELECT pg_wal_lsn_diff(:'m6_wal_end_lsn'::pg_lsn,
                       :'m6_wal_start_lsn'::pg_lsn)::bigint AS m6_batch_wal_bytes \gset
SELECT :'m6_wal_start_lsn'::pg_lsn AS start_lsn,
       :'m6_wal_end_lsn'::pg_lsn AS end_lsn,
       :m6_batch_wal_bytes::bigint AS wal_bytes,
       pg_size_pretty(:m6_batch_wal_bytes::bigint) AS wal_generated;

SELECT pg_stat_clear_snapshot();
SELECT c.num_timed - b.num_timed AS timed_delta,
       c.num_requested - b.num_requested AS requested_delta,
       c.num_done - b.num_done AS completed_delta,
       c.buffers_written - b.buffers_written AS buffers_written_delta,
       round((c.write_time - b.write_time)::numeric, 2) AS write_ms_delta,
       round((c.sync_time - b.sync_time)::numeric, 2) AS sync_ms_delta
FROM pg_stat_checkpointer AS c
CROSS JOIN m6_checkpointer_before AS b
WHERE c.stats_reset IS NOT DISTINCT FROM b.stats_reset;

\echo '\n-- WAL sizing worksheet: replace with a monitored peak claim-event rate'
\set observed_peak_claim_wal_mb_per_min 512
\set desired_checkpoint_minutes 15
\set wal_safety_factor 1.30
WITH sizing AS (
    SELECT :observed_peak_claim_wal_mb_per_min::numeric AS rate_mb_per_min,
           :desired_checkpoint_minutes::numeric AS minutes,
           :wal_safety_factor::numeric AS safety
)
SELECT rate_mb_per_min,
       minutes AS desired_minutes,
       safety,
       ceil(rate_mb_per_min * minutes * safety / 16) * 16
           AS candidate_max_wal_size_mb
FROM sizing;

SELECT name, setting, unit, context, source
FROM pg_settings
WHERE name IN ('max_wal_size', 'min_wal_size', 'checkpoint_timeout',
               'checkpoint_completion_target', 'full_page_writes')
ORDER BY name;

TRUNCATE lab_m6.claim_event_wal_probe;
-- Use a representative interval covering claim intake, attachments, status
-- transitions, and reserve changes. Consider WAL retained by archives and
-- replication slots separately.
-- Success: requested checkpoints fall, checkpoint I/O becomes smoother, disk
-- headroom remains safe, and recovery time still meets the objective.

\echo '\n-- Lab 6E: autovacuum for a high-churn claim review queue'
DROP TABLE IF EXISTS lab_m6.claim_queue_churn;
CREATE TABLE lab_m6.claim_queue_churn (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL,
    tenant_id integer NOT NULL,
    branch_code text NOT NULL,
    status text NOT NULL,
    assigned_adjuster text,
    estimated_amount numeric(12,2) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO lab_m6.claim_queue_churn (
    claim_no, tenant_id, branch_code, status, estimated_amount
)
SELECT 'CLM-QUEUE-' || lpad(g::text, 7, '0'),
       1 + (g % 100),
       (ARRAY['BKK', 'CNX', 'HKT', 'KKN'])[1 + (g % 4)],
       'NEW',
       (5000 + (g % 500000))::numeric(12,2)
FROM generate_series(1, 100000) AS g;
ANALYZE lab_m6.claim_queue_churn;

SELECT c.oid::regclass AS relation,
       c.reltuples::bigint AS estimated_rows,
       current_setting('autovacuum_vacuum_threshold')::numeric AS base_threshold,
       current_setting('autovacuum_vacuum_scale_factor')::numeric AS scale_factor,
       least(
           current_setting('autovacuum_vacuum_max_threshold')::numeric,
           current_setting('autovacuum_vacuum_threshold')::numeric
             + current_setting('autovacuum_vacuum_scale_factor')::numeric
               * c.reltuples
       )::bigint AS estimated_default_trigger
FROM pg_class AS c
WHERE c.oid = 'lab_m6.claim_queue_churn'::regclass;

UPDATE lab_m6.claim_queue_churn
SET status = 'UNDER_REVIEW',
    assigned_adjuster = 'ADJ-' || lpad((1 + claim_id % 250)::text, 4, '0'),
    updated_at = clock_timestamp()
WHERE claim_id <= 5000;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();

SELECT relname, n_live_tup, n_dead_tup, n_mod_since_analyze,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'lab_m6' AND relname = 'claim_queue_churn';

\set desired_dead_tuple_trigger 3000
\set table_base_threshold 500
WITH table_size AS (
    SELECT reltuples::numeric AS rows
    FROM pg_class WHERE oid = 'lab_m6.claim_queue_churn'::regclass
)
SELECT :desired_dead_tuple_trigger AS desired_trigger,
       :table_base_threshold AS base_threshold,
       round(greatest(0,
           (:desired_dead_tuple_trigger - :table_base_threshold) / rows), 4)
           AS calculated_scale_factor
FROM table_size;

ALTER TABLE lab_m6.claim_queue_churn SET (
    autovacuum_vacuum_threshold = 500,
    autovacuum_vacuum_scale_factor = 0.025,
    autovacuum_analyze_threshold = 500,
    autovacuum_analyze_scale_factor = 0.01
);

SELECT relname, reloptions
FROM pg_class
WHERE oid = 'lab_m6.claim_queue_churn'::regclass;

-- Observe at least several autovacuum_naptime cycles in a real test. Success:
-- dead tuples stay within the target, autovacuum completes without blocking the
-- workload, table growth stabilizes, and I/O latency remains acceptable.
-- Rollback for this lab table:
-- ALTER TABLE lab_m6.claim_queue_churn RESET (
--   autovacuum_vacuum_threshold, autovacuum_vacuum_scale_factor,
--   autovacuum_analyze_threshold, autovacuum_analyze_scale_factor
-- );

\echo '\n-- Lab 6F: logging for claim approval latency, spills, and lock waits'
SELECT name, setting, unit, context, source
FROM pg_settings
WHERE name IN ('log_min_duration_statement', 'log_temp_files',
               'log_lock_waits', 'deadlock_timeout', 'log_line_prefix')
ORDER BY name;

\set claim_diagnostic_events_per_minute 120
\set average_log_event_bytes 1800
SELECT :claim_diagnostic_events_per_minute AS events_per_minute,
       :average_log_event_bytes AS average_event_bytes,
       round(:claim_diagnostic_events_per_minute * :average_log_event_bytes
             * 60 * 24 / 1024.0 / 1024.0, 2) AS estimated_log_mb_per_day;

BEGIN;
SET LOCAL log_min_duration_statement = '500ms';
SET LOCAL log_temp_files = '16MB';
SET LOCAL log_lock_waits = on;
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('log_min_duration_statement', 'log_temp_files', 'log_lock_waits')
ORDER BY name;
SELECT pg_sleep(0.6); -- inspect make db-logs in another terminal
ROLLBACK;

-- Start from the claim approval API objective and the log pipeline capacity.
-- Success: logs identify slow approvals, reserve-report spills, and claim lock
-- waits without exceeding storage or ingestion budgets. Raise the threshold or
-- narrow the scope when volume is high and events do not lead to action.

\echo '\n-- Lab 6G: Complete the keep-or-revert decision record'
SELECT d.datname AS database_name,
       r.rolname AS role_name,
       s.setconfig
FROM pg_db_role_setting AS s
LEFT JOIN pg_database AS d ON d.oid = s.setdatabase
LEFT JOIN pg_roles AS r ON r.oid = s.setrole
ORDER BY 1, 2;

\echo 'For each ClaimSure configuration practice, record:'
\echo '1. Symptom and evidence interval'
\echo '2. Parameter and why it controls the observed component'
\echo '3. Current value, test value, scope, and activation method'
\echo '4. Calculation used to choose the value'
\echo '5. Before/after metrics and concurrency conditions'
\echo '6. Keep/revert decision, owner, and rollback command'

\echo '\n-- Final verification: transaction-local tests restored their values'
SELECT name, setting, unit, source, pending_restart
FROM pg_settings
WHERE name IN ('work_mem', 'statement_timeout', 'lock_timeout',
               'idle_in_transaction_session_timeout',
               'log_min_duration_statement', 'log_temp_files', 'log_lock_waits')
ORDER BY name;

\timing off

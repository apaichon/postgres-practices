-- =============================================================================
-- Module 6 NEW LABS: six groups, six independent SQL experiments + file exercises.
-- Full sequence / activation / rollback: labs/module06/README.md
-- Slides: docs/slides/module-06-configuration-claim.md
-- LOGIN: postgres | DATABASE: claimsure_m6 | SERVER: dedicated Module 6 instance
-- No Module 1 dependency. Only lab_m6c generated objects are created/changed.
-- Never touches insurance.claim. No SQL statement edits server configuration.
-- Use run-lab06-docker.sh: sql A ... sql F, interleaved with set/reload/restart.
-- sql all runs the SQL track only; it does NOT complete the six file exercises.
-- SQL editor: run complete START/END blocks; exclude psql backslash commands.
-- Keep one connection within each lettered lab. Reconnect after every restart.
-- =============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing on
\if :{?m6_lab}
\else
  \set m6_lab all
\endif
\if :{?m6_reset_table}
\else
  \set m6_reset_table false
\endif
SELECT :'m6_lab' IN ('all','A') AS run_a,
       :'m6_lab' IN ('all','B') AS run_b,
       :'m6_lab' IN ('all','C') AS run_c,
       :'m6_lab' IN ('all','D') AS run_d,
       :'m6_lab' IN ('all','E') AS run_e,
       :'m6_lab' IN ('all','F') AS run_f \gset

-- START 0.1 | Verify the dedicated instance and create reusable generated data
-- LOGIN: postgres | RUN: once; subsequent letters reuse the same fixture
-- EXPECT: PostgreSQL 18, claimsure_m6, cluster claimsure-module06; 100000 claim rows
DO $$
BEGIN
 IF current_setting('server_version_num')::int / 10000 <> 18 THEN
   RAISE EXCEPTION 'This lab targets PostgreSQL 18.';
 END IF;
 IF pg_is_in_recovery() OR current_database() <> 'claimsure_m6'
    OR current_setting('cluster_name') <> 'claimsure-module06' THEN
   RAISE EXCEPTION 'Use the dedicated Module 6 primary (labs/module06), not a classroom/production database.';
 END IF;
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname=current_user AND rolsuper) THEN
   RAISE EXCEPTION 'Log in as the dedicated lab postgres superuser.';
 END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS lab_m6c;
CREATE TABLE IF NOT EXISTS lab_m6c.claim (
 claim_id bigint PRIMARY KEY, claim_no text UNIQUE NOT NULL,
 policy_id bigint NOT NULL, status text NOT NULL,
 incident_at timestamptz NOT NULL, estimated_amount numeric(14,2) NOT NULL,
 approved_amount numeric(14,2), created_at timestamptz NOT NULL
);
INSERT INTO lab_m6c.claim
SELECT g, 'CLM-M6-' || lpad(g::text,7,'0'), 1+(g%500),
 (ARRAY['NEW','REVIEW','APPROVED','REJECTED','PAID'])[1+(g%5)],
 timestamptz '2026-01-01 00:00:00+00' + g*interval '1 minute',
 1000+(g%150000), CASE WHEN g%5 IN (2,4) THEN 800+(g%100000) END,
 timestamptz '2026-01-01 00:00:00+00' + g*interval '1 minute'
FROM generate_series(1,100000) g
WHERE NOT EXISTS (SELECT FROM lab_m6c.claim);
ANALYZE lab_m6c.claim;
SELECT current_database(), session_user, current_user,
       pg_postmaster_start_time(), count(*) AS generated_claim_rows
FROM lab_m6c.claim;
-- END 0.1

\echo '\n-- Lab 6A: Connections: intake capacity and time budget'
\if :run_a

-- START 6A.1 | Read connection capacity and file activation
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Baseline 40/37 ordinary slots; candidate 60/57 after restart. Slot count is not throughput.
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('max_connections','superuser_reserved_connections','reserved_connections')
ORDER BY name;
SELECT current_setting('max_connections')::int
 - current_setting('superuser_reserved_connections')::int
 - current_setting('reserved_connections')::int AS ordinary_client_ceiling;
SELECT state, count(*) AS sessions FROM pg_stat_activity
WHERE backend_type='client backend' GROUP BY state ORDER BY state;
SELECT pg_postmaster_start_time();
-- END 6A.1

-- START 6A.2 | Test a claim-intake statement budget and restore it
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: 1s / 500ms / 2min inside; prior defaults return after ROLLBACK. No intentional timeout error.
SHOW statement_timeout;
BEGIN;
SET LOCAL statement_timeout = '1s';
SET LOCAL lock_timeout = '500ms';
SET LOCAL idle_in_transaction_session_timeout = '2min';
SELECT current_setting('statement_timeout'), current_setting('lock_timeout'),
       current_setting('idle_in_transaction_session_timeout');
SELECT count(*) FROM lab_m6c.claim WHERE status='NEW';
ROLLBACK;
SHOW statement_timeout;
-- END 6A.2

\endif

\echo '\n-- Lab 6B: Memory: shared cache versus report workspace'
\if :run_b

-- START 6B.1 | Inspect the cache allocation separately from the workspace
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: shared_buffers baseline 128MB, candidate 192MB only after restart; work_mem stays 4MB.
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('shared_buffers','work_mem','hash_mem_multiplier','maintenance_work_mem')
ORDER BY name;
SELECT pg_size_pretty(pg_relation_size('lab_m6c.claim')) AS claim_table_size;
-- END 6B.1

-- START 6B.2 | Compare three work_mem values with three repeated report sorts
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Nine results; compare temp blocks, sort space and median time. SET LOCAL inside function ends at statement completion.
DROP TABLE IF EXISTS lab_m6c.work_mem_results;
CREATE TABLE lab_m6c.work_mem_results (
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

CREATE OR REPLACE FUNCTION lab_m6c.measure_open_claim_report_sort(
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
    PERFORM set_config('work_mem', p_work_mem, true);
    PERFORM set_config('max_parallel_workers_per_gather', '0', true);
    -- Keep a full Sort for this workspace experiment, including after Lab 6D's
    -- index exists. Otherwise an Incremental Sort has different JSON metrics.
    PERFORM set_config('enable_incremental_sort', 'off', true);

    EXECUTE $plan$
        EXPLAIN (ANALYZE, BUFFERS, SETTINGS, FORMAT JSON)
        SELECT claim_no, policy_id, status, incident_at,
               estimated_amount, approved_amount, created_at
        FROM lab_m6c.claim
        WHERE status IN ('NEW', 'REVIEW', 'APPROVED')
        ORDER BY policy_id, status, estimated_amount DESC, claim_no
    $plan$ INTO plan_json;

    sort_node := plan_json->0->'Plan';

    INSERT INTO lab_m6c.work_mem_results (
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

SELECT lab_m6c.measure_open_claim_report_sort(v.label, v.work_mem, r.run_no)
FROM (VALUES
    ('very_small', '64kB'),
    ('middle_test', '4MB'),
    ('candidate', '32MB')
) AS v(label, work_mem)
CROSS JOIN generate_series(1, 3) AS r(run_no);

SELECT test_label,
       tested_work_mem,
       count(*) AS runs,
       min(sort_method) AS sort_method,
       min(sort_space_type) AS sort_space_type,
       max(temp_written_blocks) AS max_temp_written_blocks,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY execution_ms)::numeric, 2)
           AS median_execution_ms,
       max(sort_space_kb) AS max_sort_space_kb
FROM lab_m6c.work_mem_results
GROUP BY test_label, tested_work_mem
ORDER BY min(measured_at);
-- END 6B.2

-- START 6B.3 | Budget report memory and verify restoration
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Illustration 256MB; session work_mem is restored. Cache size alone does not prove a faster sort.
SELECT 32 AS work_mem_mb, 4 AS reports, 2 AS sort_nodes, 1 AS processes,
       32*4*2*1 AS estimated_workspace_mb;
SHOW work_mem;
-- Add hash multipliers, launched workers and other allocations to the full budget.
-- Keep the smallest tested value meeting the workload goal; no global 32MB change.
-- END 6B.3

\endif

\echo '\n-- Lab 6C: WAL / checkpoints: event durability and pacing'
\if :run_c

-- START 6C.1 | Snapshot checkpoints and the WAL insert position
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Keep same connection for 6C.1–6C.2. Baseline max_wal_size 1GB; candidate 2GB after reload.
CREATE TABLE IF NOT EXISTS lab_m6c.claim_event (
 event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 claim_no text NOT NULL, payload jsonb NOT NULL
);
TRUNCATE lab_m6c.claim_event;
DROP TABLE IF EXISTS pg_temp.m6_wal_before;
CREATE TEMP TABLE m6_wal_before AS
SELECT clock_timestamp() AS sampled_at, pg_current_wal_insert_lsn() AS lsn, c.*
FROM pg_stat_checkpointer c;
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('fsync','full_page_writes','synchronous_commit',
 'max_wal_size','checkpoint_timeout','checkpoint_completion_target') ORDER BY name;
-- END 6C.1

-- START 6C.2 | Generate 5000 claim events and read counter deltas
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: 5000 events; WAL span > 0, valid reset epoch. Zero checkpoint deltas do not prove a sizing benefit.
INSERT INTO lab_m6c.claim_event(claim_no,payload)
SELECT 'CLM-M6-'||lpad(g::text,7,'0'),
 jsonb_build_object('event','REVIEW','amount',1000+g)
FROM generate_series(1,5000) g;
SELECT pg_stat_clear_snapshot();
SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),b.lsn)::bigint AS wal_bytes,
 round(extract(epoch FROM clock_timestamp()-b.sampled_at)::numeric,3) AS elapsed_seconds,
 c.num_timed-b.num_timed AS timed_delta,
 c.num_requested-b.num_requested AS requested_delta,
 c.num_done-b.num_done AS completed_delta,
 c.buffers_written-b.buffers_written AS written_delta,
 c.stats_reset IS NOT DISTINCT FROM b.stats_reset AS counters_comparable
FROM pg_stat_checkpointer c CROSS JOIN m6_wal_before b;
SELECT count(*) AS event_rows FROM lab_m6c.claim_event;
-- WAL span can include background work. Short checkpoint deltas may be zero.
-- Restart between runs adds a shutdown checkpoint: do not compare cumulative totals.
-- END 6C.2

\endif

\echo '\n-- Lab 6D: Planning / storage: indexed ClaimSure search'
\if :run_d

-- START 6D.1 | Prepare the same index before either planner test
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Indexed baseline/candidate uses identical query, data and index; record estimated/actual rows, buffers and time.
CREATE INDEX IF NOT EXISTS claim_policy_status_idx
ON lab_m6c.claim(policy_id,status);
ANALYZE lab_m6c.claim;
SELECT name, setting, unit, context, sourcefile
FROM pg_settings WHERE name IN ('random_page_cost','effective_cache_size',
 'effective_io_concurrency','default_statistics_target') ORDER BY name;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT claim_no, policy_id, status, estimated_amount
FROM lab_m6c.claim WHERE policy_id=1 AND status='NEW'
ORDER BY estimated_amount DESC, claim_no;
-- END 6D.1

-- START 6D.2 | Test random_page_cost narrowly before adopting a file default
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Prior file/session value restored. A plan change or speedup is not guaranteed; repeat comparable runs.
BEGIN;
SET LOCAL random_page_cost = 1.1;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT claim_no, policy_id, status, estimated_amount
FROM lab_m6c.claim WHERE policy_id=1 AND status='NEW'
ORDER BY estimated_amount DESC, claim_no;
ROLLBACK;
SHOW random_page_cost;
-- END 6D.2

\endif

\echo '\n-- Lab 6E: Parallelism: reserve aggregate and worker budgets'
\if :run_e

-- START 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: File capacity 4→8 requires restart. Per-query 0/2 needs no restart; actual launched workers may be zero.
SELECT name, setting, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('max_worker_processes','max_parallel_workers',
 'max_parallel_workers_per_gather') ORDER BY name;
BEGIN;
SET LOCAL max_parallel_workers_per_gather = 0;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT policy_id, sum(estimated_amount) AS reserve_amount
FROM lab_m6c.claim WHERE status IN ('NEW','REVIEW','APPROVED')
GROUP BY policy_id;
ROLLBACK;
BEGIN;
SET LOCAL max_parallel_workers_per_gather = 2;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT policy_id, sum(estimated_amount) AS reserve_amount
FROM lab_m6c.claim WHERE status IN ('NEW','REVIEW','APPROVED')
GROUP BY policy_id;
ROLLBACK;
SHOW max_parallel_workers_per_gather;
-- END 6E.1

-- START 6E.2 | Calculate a report process memory illustration
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Illustration 384MB for workspaces; do not raise concurrency from a single faster report.
SELECT 16 AS work_mem_mb, 2 AS sort_nodes, 3 AS leader_plus_workers,
       4 AS concurrent_reports, 16*2*3*4 AS estimated_workspace_mb;
-- Capacity ceilings do not allocate all those workers. Read EXPLAIN and CPU.
-- Account separately for hash multipliers, other worker users and shared memory.
-- END 6E.2

\endif

\echo '\n-- Lab 6F: Autovacuum: review queue churn and targeted thresholds'
\if :run_f

-- START 6F.1 | Prepare a 20000-row review queue and baseline counters
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Fresh 20000-row queue each run; cost limit 200→400 uses reload. PostgreSQL 18 worker slots require restart.
DROP TABLE IF EXISTS lab_m6c.claim_queue;
CREATE TABLE lab_m6c.claim_queue (
 claim_id bigint PRIMARY KEY, status text NOT NULL, note text NOT NULL
);
INSERT INTO lab_m6c.claim_queue SELECT g,'NEW',repeat('claim review ',8)
FROM generate_series(1,20000) g;
ANALYZE lab_m6c.claim_queue;
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('autovacuum','autovacuum_vacuum_cost_limit',
 'autovacuum_max_workers','autovacuum_worker_slots') ORDER BY name;
SELECT relname,n_live_tup,n_dead_tup,last_autovacuum,last_autoanalyze,
       autovacuum_count FROM pg_stat_user_tables WHERE relid='lab_m6c.claim_queue'::regclass;
-- END 6F.1

-- START 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Threshold 1500 unless a lower PostgreSQL 18 cap applies; 2000 REVIEW rows, autovacuum runs asynchronously.
ALTER TABLE lab_m6c.claim_queue SET (
 autovacuum_vacuum_threshold=500, autovacuum_vacuum_scale_factor=0.05,
 autovacuum_analyze_threshold=500, autovacuum_analyze_scale_factor=0.02
);
SELECT least(nullif(current_setting('autovacuum_vacuum_max_threshold')::numeric,-1),
             500+0.05*20000) AS effective_vacuum_threshold;
UPDATE lab_m6c.claim_queue SET status='REVIEW',note=note||'checked'
WHERE claim_id<=2000;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT reloptions FROM pg_class WHERE oid='lab_m6c.claim_queue'::regclass;
SELECT relname,n_live_tup,n_dead_tup,last_autovacuum,last_autoanalyze,
       autovacuum_count FROM pg_stat_user_tables WHERE relid='lab_m6c.claim_queue'::regclass;
SELECT pid,xact_start,backend_xmin,state FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL ORDER BY xact_start;
-- Poll the statistics SELECT in a NEW autocommit statement after 10–60 seconds.
-- Eligibility is not immediate completion. Tuple counts are estimates.
-- Table options persist; reset them explicitly in 6F.3.
-- END 6F.2

\if :m6_reset_table
-- START 6F.3 | Reset only the four lab table overrides
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: reloptions cleared. Optional: keep this block until AFTER observing the automatic cleanup in 6F.2.
ALTER TABLE lab_m6c.claim_queue RESET (
 autovacuum_vacuum_threshold, autovacuum_vacuum_scale_factor,
 autovacuum_analyze_threshold, autovacuum_analyze_scale_factor
);
SELECT reloptions FROM pg_class WHERE oid='lab_m6c.claim_queue'::regclass;
-- Resetting table options does NOT restore the file's cost limit.
-- Restore baseline F separately with set F baseline + reload.
-- END 6F.3
\endif

\endif

-- Optional data cleanup, only after finishing all six labs:
-- DROP SCHEMA lab_m6c CASCADE;
-- File rollback is separate: follow the baseline steps in labs/module06/README.md.

\set ON_ERROR_STOP on
\pset pager off
\timing on
\echo '=== Module 3: Performance Tuning ==='

-- Lab 3 — Performance Evidence and Reporting Structures
-- Run all: ./scripts/shells/run-lab03.sh --student xx --ask-pass all
-- Run one: ./scripts/shells/run-lab03.sh --student xx --ask-pass A
--
-- Lab 3A  Compare a slow plan with a partial covering index
-- Lab 3B  Match expression, GIN, and BRIN indexes to query shapes
-- Lab 3C  Collect index and autovacuum maintenance evidence
-- Lab 3D  Build and verify a monthly range-partitioned report table
-- Lab 3E  Build a materialized summary and dashboard snapshot

-- Workload: 2,000,000 claims across 1,200 policies.
-- Lower the claim series (for example 20000) on a slow client.
-- These are plain integers so SQLTools and other non-psql clients can run the INSERT.
-- Dedicated *_perf tables stay separate from ClaimSure starter data.

CREATE SCHEMA IF NOT EXISTS insurance;

DROP TABLE IF EXISTS insurance.claim_perf;
DROP TABLE IF EXISTS insurance.policy_perf;

CREATE UNLOGGED TABLE insurance.policy_perf (
    policy_id bigint PRIMARY KEY,
    tenant_id bigint NOT NULL,
    policy_no text NOT NULL UNIQUE,
    product_code text NOT NULL,
    status text NOT NULL
);

CREATE UNLOGGED TABLE insurance.claim_perf (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    policy_id bigint NOT NULL,
    policy_no text NOT NULL,
    claim_no text NOT NULL UNIQUE,
    branch_code text NOT NULL,
    status text NOT NULL,
    incident_at timestamptz NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    description text,
    metadata jsonb NOT NULL DEFAULT '{}'
);

INSERT INTO insurance.policy_perf
    (policy_id, tenant_id, policy_no, product_code, status)
SELECT g,
       1 + (g % 20),
       'POL-PERF-' || lpad(g::text, 5, '0'),
       (ARRAY['AUTO','HOME','TRAVEL','HEALTH'])[1 + (g % 4)],
       (ARRAY['ACTIVE','ACTIVE','ACTIVE','EXPIRED','CANCELLED'])[1 + (g % 5)]
FROM generate_series(1, 1200) AS g;

TRUNCATE insurance.claim_perf RESTART IDENTITY;
INSERT INTO insurance.claim_perf
    (tenant_id, policy_id, policy_no, claim_no, branch_code, status,
     incident_at, estimated_amount, description, metadata)
SELECT 1 + (g % 20),
       1 + (g % 1200),
       'POL-PERF-' || lpad((1 + (g % 1200))::text, 5, '0'),
       'PERF-' || lpad(g::text, 8, '0'),
       (ARRAY['BKK','CNX','HKT','KKN'])[1 + (g % 4)],
       (ARRAY['NEW','UNDER_REVIEW','APPROVED','REJECTED','PAID','CLOSED'])[1 + (g % 6)],
       TIMESTAMPTZ '2025-01-01 00:00+07' + (g % 525600) * interval '1 minute',
       1000 + (g % 150000),
       CASE WHEN g % 20 = 0 THEN 'urgent vehicle accident' ELSE 'standard claim intake' END,
       jsonb_build_object(
           'channel', (ARRAY['web','mobile','agent'])[1 + (g % 3)],
           'risk_score', g % 100,
           'vehicle', jsonb_build_object('province', (ARRAY['Bangkok','Chiang Mai','Phuket'])[1 + (g % 3)])
       )
FROM generate_series(1, 2000000) AS g;

ANALYZE insurance.policy_perf;
ANALYZE insurance.claim_perf;

\echo '\n-- Lab 3A: baseline plan for the slow claim search'
DROP INDEX IF EXISTS insurance.idx_claim_perf_open_tenant_incident;

EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS)
SELECT claim_id, claim_no, incident_at, estimated_amount
FROM insurance.claim_perf
WHERE tenant_id = 1
  AND status = 'NEW'
ORDER BY incident_at DESC
LIMIT 50;

CREATE INDEX IF NOT EXISTS idx_claim_perf_open_tenant_incident
ON insurance.claim_perf (tenant_id, incident_at DESC)
INCLUDE (claim_no, estimated_amount)
WHERE status = 'NEW';
ANALYZE insurance.claim_perf;

\echo '\n-- Compare: planner should prefer the partial covering index'
EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS)
SELECT claim_id, claim_no, incident_at, estimated_amount
FROM insurance.claim_perf
WHERE tenant_id = 1
  AND status = 'NEW'
ORDER BY incident_at DESC
LIMIT 50;

\echo '\n-- Lab 3B: match index type to access pattern'
CREATE INDEX IF NOT EXISTS idx_claim_perf_lower_claim_no
    ON insurance.claim_perf (lower(claim_no));
CREATE INDEX IF NOT EXISTS idx_claim_perf_metadata_gin
    ON insurance.claim_perf USING gin (metadata jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_claim_perf_incident_brin
    ON insurance.claim_perf USING brin (incident_at) WITH (pages_per_range = 32);

EXPLAIN (ANALYZE, BUFFERS)
SELECT claim_no FROM insurance.claim_perf
WHERE lower(claim_no) = lower('PERF-00001000');

-- {"channel":"mobile"} alone matches about 1/3 of the table, so GIN still
-- Bitmap-Heap-Scans hundreds of thousands of rows. Pair a second key to
-- make containment selective enough that the index looks cheap.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM insurance.claim_perf
WHERE metadata @> '{"channel":"mobile","risk_score": 7}'::jsonb;

\echo '\n-- Lab 3C: index and autovacuum maintenance evidence'
SELECT indexrelname,
       idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'insurance'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Practice: size table autovacuum from live rows and a dead-tuple budget.
-- vacuum_trigger = threshold + scale_factor * n_live_tup
-- scale_factor   = (desired_dead - threshold) / n_live_tup
SELECT relname,
       n_live_tup,
       current_setting('autovacuum_vacuum_threshold')::numeric AS cluster_threshold,
       current_setting('autovacuum_vacuum_scale_factor')::numeric AS cluster_scale,
       (current_setting('autovacuum_vacuum_threshold')::numeric
          + current_setting('autovacuum_vacuum_scale_factor')::numeric
            * n_live_tup)::bigint AS cluster_trigger,
       1000 AS table_threshold,
       0.05::numeric AS table_scale,
       (1000 + 0.05 * n_live_tup)::bigint AS lab_table_trigger,
       round((100000 - 1000) / GREATEST(n_live_tup, 1)::numeric, 4)
           AS scale_for_100k_dead
FROM pg_stat_user_tables
WHERE schemaname = 'insurance'
  AND relname = 'claim_perf';

-- one_pass_tids ≈ autovacuum_work_mem / 6 bytes (uses maintenance_work_mem when -1)
SELECT current_setting('shared_buffers') AS shared_buffers,
       current_setting('maintenance_work_mem') AS maintenance_work_mem,
       current_setting('autovacuum_work_mem') AS autovacuum_work_mem,
       current_setting('autovacuum_max_workers') AS autovacuum_max_workers,
       (pg_size_bytes(COALESCE(NULLIF(current_setting('autovacuum_work_mem'), '-1'),
                               current_setting('maintenance_work_mem'))) / 6)
           AS one_pass_dead_tids;

ALTER TABLE insurance.claim_perf SET (
    autovacuum_vacuum_scale_factor = 0.05,
    autovacuum_analyze_scale_factor = 0.02,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_analyze_threshold = 500
);

VACUUM (ANALYZE) insurance.claim_perf;

SELECT relname, n_live_tup, n_dead_tup,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'insurance';

-- Use only after measuring bloat and during a suitable maintenance window:
-- REINDEX INDEX CONCURRENTLY insurance.idx_claim_perf_lower_claim_no;

\echo '\n-- Lab 3D: monthly range partition table'
CREATE TABLE IF NOT EXISTS insurance.claim_report (
    claim_id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    status text NOT NULL,
    incident_at timestamptz NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    PRIMARY KEY (claim_id, incident_at)
) PARTITION BY RANGE (incident_at);

CREATE TABLE IF NOT EXISTS insurance.claim_report_2025_01
PARTITION OF insurance.claim_report
FOR VALUES FROM ('2025-01-01 00:00+07') TO ('2025-02-01 00:00+07');
CREATE TABLE IF NOT EXISTS insurance.claim_report_2025_02
PARTITION OF insurance.claim_report
FOR VALUES FROM ('2025-02-01 00:00+07') TO ('2025-03-01 00:00+07');
CREATE TABLE IF NOT EXISTS insurance.claim_report_2025_03
PARTITION OF insurance.claim_report
FOR VALUES FROM ('2025-03-01 00:00+07') TO ('2025-04-01 00:00+07');

TRUNCATE insurance.claim_report;
INSERT INTO insurance.claim_report
SELECT claim_id, tenant_id, status, incident_at, estimated_amount
FROM insurance.claim_perf
WHERE incident_at >= TIMESTAMPTZ '2025-01-01 00:00+07'
  AND incident_at <  TIMESTAMPTZ '2025-04-01 00:00+07';
ANALYZE insurance.claim_report;

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(estimated_amount)
FROM insurance.claim_report
WHERE incident_at >= TIMESTAMPTZ '2025-02-01 00:00+07'
  AND incident_at <  TIMESTAMPTZ '2025-03-01 00:00+07';

SELECT tableoid::regclass AS partition_name, count(*) AS rows
FROM insurance.claim_report
GROUP BY tableoid
ORDER BY tableoid::regclass::text;

\echo '\n-- Lab 3E: materialized report and denormalized snapshot'
CREATE MATERIALIZED VIEW IF NOT EXISTS insurance.monthly_claim_summary AS
SELECT date_trunc('month', incident_at)::date AS month_start,
       tenant_id,
       status,
       count(*) AS claim_count,
       sum(estimated_amount) AS total_estimated
FROM insurance.claim_perf
GROUP BY 1, 2, 3
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS ux_monthly_claim_summary
ON insurance.monthly_claim_summary (month_start, tenant_id, status);

REFRESH MATERIALIZED VIEW insurance.monthly_claim_summary;

SELECT *
FROM insurance.monthly_claim_summary
ORDER BY month_start DESC, tenant_id, status
LIMIT 20;

CREATE TABLE IF NOT EXISTS insurance.claim_dashboard_snapshot (
    tenant_id bigint PRIMARY KEY,
    open_claims bigint NOT NULL,
    total_estimated numeric(18,2) NOT NULL,
    refreshed_at timestamptz NOT NULL
);

INSERT INTO insurance.claim_dashboard_snapshot
    (tenant_id, open_claims, total_estimated, refreshed_at)
SELECT tenant_id,
       count(*) FILTER (WHERE status IN ('NEW','UNDER_REVIEW')),
       coalesce(sum(estimated_amount), 0),
       clock_timestamp()
FROM insurance.claim_perf
GROUP BY tenant_id
ON CONFLICT (tenant_id) DO UPDATE
SET open_claims = EXCLUDED.open_claims,
    total_estimated = EXCLUDED.total_estimated,
    refreshed_at = EXCLUDED.refreshed_at;

SELECT * FROM insurance.claim_dashboard_snapshot ORDER BY tenant_id;

\echo '\nValidation'
SELECT count(*) AS generated_rows,
       count(DISTINCT policy_id) AS generated_policies
FROM insurance.claim_perf;
\timing off

-- =============================================================================
-- Module 5: PostgreSQL Architecture With Labs
-- Source: slides/postgres-admin-v3/
--         postgres-admin-v3-complete-course-enterprise-blue.pdf, pages 101-123.
-- The overview on page 103 uses 1A-1G; detailed slides use 5A-5G, followed here.
-- Run: make sql-v3 LAB=05-architecture.sql
-- Run one section: make lab5 LAB_NO=5D.1 (use LAB_NO=list to show choices).
-- Requires: psql, the seeded ClaimSure primary, and the postgres lab role.
-- Run with autocommit enabled, not psql --single-transaction.
-- Lab 5A needs a second connection; Lab 5E uses the two MVCC session files.
-- D.1 commits a timestamp update; C/D.2-D.4 roll back their changes.
-- F commits 1,000 audit events, measures WAL, then deletes only its own rows.
-- Rollback/cleanup do not undo WAL generation or identity sequence advances.
-- =============================================================================
\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 5: PostgreSQL Architecture ==='
\conninfo

DO $$
BEGIN
    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Run Module 5 on the ClaimSure primary, not a standby.';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'Run this architecture lab as the postgres lab superuser.';
    END IF;
    IF to_regclass('insurance.claim') IS NULL
       OR to_regclass('insurance.audit_event') IS NULL THEN
        RAISE EXCEPTION 'Load the ClaimSure schema and seed data from init/ first.';
    END IF;
    IF NOT EXISTS (SELECT FROM insurance.claim
                   WHERE tenant_id = 1 AND claim_no = 'CLM-1001') THEN
        RAISE EXCEPTION 'Missing seed claim: tenant 1 / CLM-1001.';
    END IF;
END
$$;

\echo '\n-- Lab 5A: Observe Connections (PDF pp. 105-106)'
-- Open two terminals from the repository root:
--   ./scripts/psql.sh postgres
--   ./scripts/psql.sh claim_app
-- In each, run SELECT pg_backend_pid(); then inspect activity as postgres.
SELECT pg_backend_pid() AS backend_pid,
       current_database() AS database_name,
       current_user AS database_user,
       inet_client_addr() AS client_address,
       pg_postmaster_start_time() AS server_started_at;

SELECT pid, backend_type, usename, application_name, client_addr, state,
       query_start, wait_event_type, wait_event, left(query, 80) AS query
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY pid;
-- VERIFY: each direct session has a different PID; idle sessions keep a backend.

\echo '\n-- Lab 5B: Background Process Evidence (PDF pp. 107-108)'
SELECT pid, backend_type, state, wait_event_type, wait_event
FROM pg_stat_activity
WHERE backend_type <> 'client backend'
ORDER BY backend_type, pid;

SELECT * FROM pg_stat_bgwriter;
SELECT to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL AS has_checkpointer \gset
\if :has_checkpointer
SELECT * FROM pg_stat_checkpointer;
\else
\echo 'Before PostgreSQL 17, checkpoint counters are included in pg_stat_bgwriter.'
\endif
SELECT * FROM pg_stat_wal;
-- VERIFY: find background writer, checkpointer, WAL writer and autovacuum launcher.
-- Workers appear only when needed; archiver depends on archive configuration.
-- Counters are cumulative and can lag; repeat after the writes in 5D/5F.

\echo '\n-- Lab 5C: Shared Memory in a Claim Update (PDF pp. 109-110)'
SHOW shared_buffers;
SHOW wal_buffers;
SHOW max_connections;
SHOW work_mem;
-- shared_buffers and wal_buffers are shared; work_mem is per operation.
-- effective_cache_size is a planner estimate, not allocated memory.
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('effective_cache_size', 'maintenance_work_mem')
ORDER BY name;

-- Claim columns: claim_id, claim_no, policy_id, status, incident_at,
-- estimated_amount, approved_amount, created_at.
-- CLM-L1-005 starts as NEW. The update below is rolled back.
SELECT claim_id, claim_no, policy_id, status, incident_at,
       estimated_amount, approved_amount, created_at
FROM insurance.claim
ORDER BY claim_id;

BEGIN;
UPDATE insurance.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-005'
RETURNING claim_id, claim_no, policy_id, status, incident_at,
          estimated_amount, approved_amount, created_at;

SELECT locktype, relation::regclass AS relation, transactionid, mode, granted
FROM pg_locks
WHERE pid = pg_backend_pid()
ORDER BY locktype, mode;
ROLLBACK;

-- VERIFY: the read lists the claim columns above.
-- UPDATE returns CLM-L1-005 with status REVIEW.
-- ROLLBACK restores NEW. Relation/transaction locks exist before rollback.
-- Row locks are normally stored in tuple headers, not all listed in pg_locks.

\echo '\n-- Lab 5D: Data Page and Tuple States (PDF pp. 111-112)'
-- Dirty/clean describes a buffer page; live/old/deleted/dead describes tuples.
-- ctid is (block number, tuple slot), not a stable business key.
-- xmin identifies the inserting transaction. xmax can represent deletion,
-- update or locking; a nonzero xmax alone does not prove a tuple is dead.
-- Ask: show the example data stored in one tuple.
-- Header: ctid, xmin, xmax. Column values: the CLM-L1-005 claim row.
SELECT ctid, xmin, xmax,
       claim_id, claim_no, policy_id, status,
       incident_at, estimated_amount, approved_amount, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';


\echo '\n-- Lab 5D.1: Page Lifecycle (PDF p. 113)'
SHOW shared_buffers;
SELECT pg_current_wal_insert_lsn() AS page_before_lsn \gset
BEGIN;
SET LOCAL synchronous_commit = on;
-- claim has created_at, not updated_at.
-- This commit replaces created_at on CLM-L1-005. status stays NEW.
UPDATE insurance.claim
SET created_at = clock_timestamp()
WHERE claim_no = 'CLM-L1-005'
RETURNING ctid, xmin, xmax, claim_no, status, created_at;
COMMIT;

SELECT :'page_before_lsn'::pg_lsn AS before_lsn,
       pg_current_wal_insert_lsn() AS after_lsn,
       pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'page_before_lsn'::pg_lsn) AS wal_bytes;
-- VERIFY: WAL advanced. With fsync enabled and synchronous_commit=on, commit
-- waits for local WAL flush; it need not wait for the changed heap page write.
-- Background writer/checkpointer (and sometimes backends) write dirty pages.
-- An LSN change is WAL evidence, not a direct measurement of buffer dirtiness.

\echo '\n-- Lab 5D.2: INSERT New Live Tuple (PDF p. 114)'
BEGIN;
INSERT INTO insurance.audit_event (
    tenant_id, actor, action, entity_type, entity_id, details
)
VALUES (1, current_user, 'PAGE_STATE_LAB', 'claim', 'CLM-1001',
        '{"activity":"insert"}'::jsonb)
RETURNING ctid, xmin, xmax, event_id, action;
ROLLBACK;
-- VERIFY: INSERT returns a tuple with xmin. This transaction sees its own insert;
-- other sessions would see it only after commit. Here rollback removes it.

\echo '\n-- Lab 5D.3: UPDATE Old Tuple Plus New Tuple (PDF p. 115)'
BEGIN;
SELECT ctid, xmin, xmax, claim_no, status
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';

UPDATE insurance.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-005'
RETURNING ctid, xmin, xmax, claim_no, status;
ROLLBACK;
-- VERIFY: compare ctid/xmin before and after. UPDATE creates a replacement
-- tuple; ordinary SELECT does not expose every physical version on the page.

\echo '\n-- Lab 5D.4: DELETE and SELECT Visibility (PDF p. 116)'
-- D.2 rolled back its insert, so create a dedicated row for this DELETE.
-- Track its identity: never delete other learners' PAGE_STATE_LAB events.
BEGIN;
INSERT INTO insurance.audit_event (
    tenant_id, actor, action, entity_type, entity_id, details
)
VALUES (1, current_user, 'PAGE_STATE_LAB', 'claim', 'CLM-1001',
        '{"activity":"delete"}'::jsonb)
RETURNING event_id AS delete_event_id \gset

SAVEPOINT before_delete;
DELETE FROM insurance.audit_event
WHERE event_id = :delete_event_id
RETURNING ctid, xmin, xmax, event_id, action;

SELECT count(*) AS visible_after_delete
FROM insurance.audit_event WHERE event_id = :delete_event_id;
ROLLBACK TO SAVEPOINT before_delete;
SELECT count(*) AS visible_after_undo_delete
FROM insurance.audit_event WHERE event_id = :delete_event_id;

ROLLBACK;
-- VERIFY: DELETE returns one row; visibility counts are 0 then 1.
-- The outer rollback removes the fixture. DELETE does not immediately compact
-- the heap; versions become reclaimable when no active snapshot needs them.

\echo '\n-- Lab 5D.5: Activity to Tuple-State Map (PDF p. 117)'
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum,
       vacuum_count, autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'insurance' AND relname IN ('claim', 'audit_event')
ORDER BY relname;
-- These are estimates, not an immediate tuple-by-tuple visibility inventory.
-- SELECT: snapshot visibility; no new version (hint bits may dirty a page).
-- INSERT: new version. UPDATE: old + new versions. DELETE: removed version.
-- VACUUM: reclaims versions no snapshot needs; space can be reused.
-- CHECKPOINT: writes dirty pages; does not change transaction visibility.
-- Discussion only: no forced CHECKPOINT or VACUUM is needed for this lab.

\echo '\n-- Lab 5E: MVCC Lab Example (PDF p. 118)'
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';

-- Run these in two terminals, both connected as postgres to the same primary.
-- Terminal A (interactive; wait at its prompt):
--   docker compose exec primary psql -X -U postgres -d claimsure \
--     -f /sql/postgres-admin-v3/05-mvcc-session-a.sql
-- Terminal B (after A has taken its first snapshot):
--   docker compose exec primary psql -X -U postgres -d claimsure \
--     -f /sql/postgres-admin-v3/05-mvcc-session-b.sql
-- Return to A and press Enter only after B commits.
-- VERIFY: A keeps its original status/created_at/ctid while its Repeatable Read
-- transaction is open. Its first SELECT after COMMIT sees B's new version.
-- B commits REVIEW. On repeat runs the status may already match;
-- created_at and ctid still demonstrate that A sees an older version.
\echo 'Two-session exercise: run 05-mvcc-session-a.sql, then 05-mvcc-session-b.sql.'

\echo '\n-- Lab 5F: WAL Lab Example (PDF pp. 119-120)'
-- Capture LSNs in separate statements so the start is sampled before INSERT.
-- Retain only this batch's IDs for cleanup after the durable commit observation.
CREATE TEMP TABLE lab_m5_wal_event_ids (event_id bigint PRIMARY KEY);
SELECT pg_current_wal_insert_lsn() AS wal_before_lsn \gset
BEGIN;
SET LOCAL synchronous_commit = on;
WITH ins AS (
    INSERT INTO insurance.audit_event (
        tenant_id, actor, action, entity_type, entity_id, details
    )
    SELECT 1, 'load_lab', 'CLAIM_VIEWED', 'claim', g::text,
           jsonb_build_object('source', 'lab_m5_wal')
    FROM generate_series(1, 1000) AS g
    RETURNING event_id
)
INSERT INTO lab_m5_wal_event_ids SELECT event_id FROM ins;
SELECT pg_current_wal_insert_lsn() AS wal_batch_end_lsn \gset
COMMIT;

SELECT count(*) AS rows_inserted,
       :'wal_before_lsn'::pg_lsn AS start_lsn,
       :'wal_batch_end_lsn'::pg_lsn AS batch_end_lsn,
       pg_wal_lsn_diff(:'wal_batch_end_lsn'::pg_lsn, :'wal_before_lsn'::pg_lsn) AS wal_bytes,
       pg_size_pretty(pg_wal_lsn_diff(
           :'wal_batch_end_lsn'::pg_lsn, :'wal_before_lsn'::pg_lsn)) AS wal_generated,
       pg_current_wal_flush_lsn() >= :'wal_batch_end_lsn'::pg_lsn AS batch_wal_flushed
FROM lab_m5_wal_event_ids;
-- VERIFY: 1,000 rows, positive WAL bytes, batch_wal_flushed = true.
-- LSNs are cluster-wide; concurrent writes can contribute to the measured delta.
-- The batch end is before COMMIT; the commit record adds further WAL.

-- Remove exactly this run's events after measuring; cleanup generates more WAL.
DELETE FROM insurance.audit_event AS e
USING lab_m5_wal_event_ids AS batch
WHERE e.event_id = batch.event_id;
DROP TABLE lab_m5_wal_event_ids;

SELECT pg_current_wal_insert_lsn() AS insert_lsn,
       pg_current_wal_lsn() AS write_lsn,
       pg_current_wal_flush_lsn() AS flush_lsn,
       pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file;

SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('wal_level', 'max_wal_size', 'min_wal_size', 'checkpoint_timeout',
               'archive_mode', 'archive_command', 'fsync', 'full_page_writes',
               'synchronous_commit')
ORDER BY name;

\echo '\n-- Lab 5G: Storage and PGDATA Lab Example (PDF p. 121)'
SHOW data_directory;
SHOW config_file;
SHOW hba_file;
SHOW block_size;
SHOW data_checksums;

SELECT oid, datname FROM pg_database ORDER BY oid;
SELECT pg_relation_filepath('insurance.claim') AS claim_file,
       pg_size_pretty(pg_relation_size('insurance.claim')) AS claim_heap_size,
       pg_size_pretty(pg_total_relation_size('insurance.claim')) AS claim_total_size;

SELECT c.oid::regclass AS relation, c.relkind,
       pg_relation_filepath(c.oid) AS relation_file,
       pg_size_pretty(pg_relation_size(c.oid)) AS heap_or_index,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_with_aux
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'insurance' AND c.relkind IN ('r', 'i', 'p')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 20;

SELECT spcname, pg_tablespace_location(oid) AS location
FROM pg_tablespace ORDER BY spcname;
SELECT name, pg_size_pretty(size) AS size, modification
FROM pg_ls_waldir()
ORDER BY modification DESC, name
LIMIT 10;
-- VERIFY: the relation path is relative to PGDATA; its database OID matches
-- pg_database for default-tablespace storage. Never edit PGDATA/delete pg_wal.

\echo '\n-- Concept Check and Architecture Recap (PDF pp. 122-123)'
-- Narrate CLM-1001: connection -> backend -> snapshot -> shared buffers/locks
-- -> new tuple version -> WAL flush for durable commit -> later page writeback
-- -> vacuum cleanup when old versions are no longer needed.
-- Point to one observation from 5A-5G for each step.

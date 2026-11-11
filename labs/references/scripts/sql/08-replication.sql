\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 8: Replication and High Availability ==='
\conninfo

CREATE SCHEMA IF NOT EXISTS lab_m8;
CREATE TABLE IF NOT EXISTS lab_m8.logical_claim (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL UNIQUE,
    status text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO lab_m8.logical_claim(claim_no, status)
VALUES ('REPL-001', 'NEW')
ON CONFLICT (claim_no) DO UPDATE
SET status = EXCLUDED.status, updated_at = clock_timestamp();

\echo '\n-- Lab 8A/8B: primary or standby, senders and receiver'
SELECT pg_is_in_recovery() AS is_standby,
       CASE WHEN pg_is_in_recovery()
            THEN pg_last_wal_replay_lsn()
            ELSE pg_current_wal_lsn() END AS current_position;

SELECT pid, application_name, client_addr, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS byte_lag
FROM pg_stat_replication
ORDER BY application_name;

SELECT status, sender_host, sender_port, slot_name,
       written_lsn, flushed_lsn, latest_end_lsn,
       last_msg_receipt_time
FROM pg_stat_wal_receiver;

\echo '\n-- Lab 8C: lag dimensions and replay delay'
SELECT application_name,
       write_lag, flush_lag, replay_lag,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS retained_bytes
FROM pg_stat_replication
ORDER BY application_name;

SELECT slot_name, slot_type, active, restart_lsn, confirmed_flush_lsn,
       wal_status, safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;

\echo '\n-- Synchronous replication policy (observe; do not change blindly)'
SELECT name, setting, source
FROM pg_settings
WHERE name IN ('synchronous_commit','synchronous_standby_names',
               'max_wal_senders','max_replication_slots','wal_keep_size')
ORDER BY name;

\echo '\n-- Lab 8D: logical publication on the primary'
SELECT pg_is_in_recovery() AS in_recovery \gset
\if :in_recovery
\echo 'Skip publication creation: this server is a standby.'
\else
DO $block$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname = 'lab_m8_claim_publication') THEN
        CREATE PUBLICATION lab_m8_claim_publication
        FOR TABLE lab_m8.logical_claim;
    END IF;
END
$block$;

SELECT p.pubname, p.pubinsert, p.pubupdate, p.pubdelete,
       n.nspname AS schema_name, c.relname AS table_name
FROM pg_publication p
LEFT JOIN pg_publication_rel pr ON pr.prpubid = p.oid
LEFT JOIN pg_class c ON c.oid = pr.prrelid
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE p.pubname = 'lab_m8_claim_publication';
\endif

\echo '\n-- Subscription health (empty until a subscriber is configured)'
SELECT subname, pid, relid::regclass, received_lsn,
       last_msg_send_time, last_msg_receipt_time,
       latest_end_lsn, latest_end_time
FROM pg_stat_subscription
ORDER BY subname, relid;

\echo '\n-- Lab 8E: routing evidence for direct/PgBouncer/HAProxy connections'
SELECT inet_server_addr() AS server_ip,
       inet_server_port() AS server_port,
       pg_is_in_recovery() AS is_replica,
       current_setting('transaction_read_only') AS transaction_read_only;

\echo 'From the host, compare endpoints:'
\echo '  make psql             # direct primary'
\echo '  make replica          # direct replica'
\echo '  make pgbouncer        # pooled write connection'
\echo '  make haproxy-write    # HAProxy primary endpoint'
\echo '  make haproxy-read     # HAProxy replica endpoint'
\echo 'Inside PgBouncer admin DB use SHOW POOLS; and SHOW STATS;'

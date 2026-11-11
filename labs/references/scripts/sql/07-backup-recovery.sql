-- =============================================================================
-- Module 7: ClaimSure Backup and Recovery Practice
--
-- Classroom students use the shell runner, not this file:
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass logical
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass physical
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass snapshot
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass pitr
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass all
-- That runner reads claimsure_xx and restores schema insurance into
-- claimsure_backup_xx. It does not pg_basebackup or recover the shared cluster.
--
-- The SQL below is the superuser practice. It expects PostgreSQL 18 and the
-- postgres lab role. Students should not Execute All of this file.
-- Run all:        make lab-v3 LAB_NO=07
-- Run one lab:    make lab-v3 LAB_NO=lab07-A
-- Direct runner:  ./scripts/run-module7-lab.sh lab07-F
-- Requires: PostgreSQL 18, the ClaimSure primary, and the postgres lab role.
--
-- The SQL practices inspect readiness, capture business evidence, and create a
-- named restore point. Backup and restore commands remain explicit shell steps
-- because a recovery drill must not overwrite the running ClaimSure primary.
-- =============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing on

\if :{?snapshot}
\else
\set snapshot 'before_backup'
\endif
\if :{?claim_rpo_minutes}
\else
\set claim_rpo_minutes 15
\endif
\if :{?claim_rto_minutes}
\else
\set claim_rto_minutes 60
\endif
\if :{?peak_claims_per_minute}
\else
\set peak_claims_per_minute 40
\endif
\if :{?restore_point}
\else
\set restore_point 'claimsure_before_recovery_drill'
\endif

\echo '=== Module 7: ClaimSure Backup and Recovery ==='
\conninfo

DO $$
BEGIN
    IF current_setting('server_version_num')::int < 180000 THEN
        RAISE EXCEPTION 'This lab targets PostgreSQL 18 or newer; server is %', version();
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'Run this recovery lab as the postgres lab superuser.';
    END IF;
END
$$;

CREATE SCHEMA IF NOT EXISTS lab_m7;

CREATE TABLE IF NOT EXISTS lab_m7.recovery_objective (
    service_name text PRIMARY KEY,
    rpo_minutes integer NOT NULL CHECK (rpo_minutes >= 0),
    rto_minutes integer NOT NULL CHECK (rto_minutes > 0),
    peak_business_rows_per_minute integer NOT NULL CHECK (peak_business_rows_per_minute >= 0),
    owner_name text NOT NULL,
    reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS lab_m7.validation_run (
    run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    snapshot_name text NOT NULL,
    captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    database_name name NOT NULL,
    server_version text NOT NULL,
    function_count bigint NOT NULL,
    procedure_count bigint NOT NULL
);

-- Upgrade validation data created by the earlier Module 7 lab in place.
ALTER TABLE lab_m7.validation_run
    ADD COLUMN IF NOT EXISTS server_version text;
UPDATE lab_m7.validation_run
SET server_version = current_setting('server_version')
WHERE server_version IS NULL;
ALTER TABLE lab_m7.validation_run
    ALTER COLUMN server_version SET NOT NULL;

CREATE TABLE IF NOT EXISTS lab_m7.table_validation (
    run_id bigint NOT NULL REFERENCES lab_m7.validation_run ON DELETE CASCADE,
    schema_name name NOT NULL,
    table_name name NOT NULL,
    row_count bigint NOT NULL,
    timestamp_column name,
    min_timestamp timestamptz,
    max_timestamp timestamptz,
    PRIMARY KEY (run_id, schema_name, table_name)
);

CREATE TABLE IF NOT EXISTS lab_m7.recovery_evidence (
    evidence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    exercise_name text NOT NULL,
    artifact_uri text,
    verification_method text NOT NULL,
    result text NOT NULL CHECK (result IN ('PASS', 'FAIL', 'NOT_RUN')),
    measured_rpo_minutes numeric,
    measured_rto_minutes numeric,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    notes text
);

CREATE OR REPLACE FUNCTION lab_m7.capture_validation(p_snapshot_name text)
RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_run_id bigint;
    v_table record;
    v_timestamp_column name;
    v_count bigint;
    v_min timestamptz;
    v_max timestamptz;
BEGIN
    INSERT INTO lab_m7.validation_run(
        snapshot_name, database_name, server_version,
        function_count, procedure_count
    )
    SELECT p_snapshot_name, current_database(), current_setting('server_version'),
           count(*) FILTER (WHERE p.prokind IN ('f', 'a', 'w')),
           count(*) FILTER (WHERE p.prokind = 'p')
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'lab_m7')
      AND n.nspname !~ '^pg_toast'
    RETURNING run_id INTO v_run_id;

    FOR v_table IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'lab_m7')
          AND schemaname !~ '^pg_toast'
        ORDER BY schemaname, tablename
    LOOP
        SELECT c.column_name
        INTO v_timestamp_column
        FROM information_schema.columns AS c
        WHERE c.table_schema = v_table.schemaname
          AND c.table_name = v_table.tablename
          AND c.data_type IN (
              'timestamp with time zone', 'timestamp without time zone', 'date'
          )
        ORDER BY CASE c.column_name
            WHEN 'updated_at' THEN 1
            WHEN 'created_at' THEN 2
            WHEN 'event_time' THEN 3
            WHEN 'incident_at' THEN 4
            WHEN 'paid_at' THEN 5
            ELSE 10
        END, c.ordinal_position
        LIMIT 1;

        IF v_timestamp_column IS NULL THEN
            EXECUTE format('SELECT count(*) FROM %I.%I',
                           v_table.schemaname, v_table.tablename)
            INTO v_count;
            v_min := NULL;
            v_max := NULL;
        ELSE
            EXECUTE format(
                'SELECT count(*), min(%I)::timestamptz, max(%I)::timestamptz FROM %I.%I',
                v_timestamp_column, v_timestamp_column,
                v_table.schemaname, v_table.tablename
            ) INTO v_count, v_min, v_max;
        END IF;

        INSERT INTO lab_m7.table_validation(
            run_id, schema_name, table_name, row_count,
            timestamp_column, min_timestamp, max_timestamp
        ) VALUES (
            v_run_id, v_table.schemaname, v_table.tablename, v_count,
            v_timestamp_column, v_min, v_max
        );
        v_timestamp_column := NULL;
    END LOOP;

    RETURN v_run_id;
END
$function$;

INSERT INTO lab_m7.recovery_objective(
    service_name, rpo_minutes, rto_minutes,
    peak_business_rows_per_minute, owner_name, reviewed_at
)
VALUES (
    'ClaimSure claim processing', :claim_rpo_minutes, :claim_rto_minutes,
    :peak_claims_per_minute, 'claims-platform', clock_timestamp()
)
ON CONFLICT (service_name) DO UPDATE
SET rpo_minutes = EXCLUDED.rpo_minutes,
    rto_minutes = EXCLUDED.rto_minutes,
    peak_business_rows_per_minute = EXCLUDED.peak_business_rows_per_minute,
    owner_name = EXCLUDED.owner_name,
    reviewed_at = EXCLUDED.reviewed_at;

\echo '\n-- Lab 7A: ClaimSure recovery objectives and exposure'
SELECT service_name, rpo_minutes, rto_minutes,
       peak_business_rows_per_minute,
       rpo_minutes * peak_business_rows_per_minute AS claims_at_risk_at_peak,
       owner_name, reviewed_at
FROM lab_m7.recovery_objective;

SELECT current_database() AS database_name,
       pg_size_pretty(pg_database_size(current_database())) AS database_size,
       count(*) AS claim_rows,
       min(created_at) AS oldest_claim,
       max(updated_at) AS latest_claim_change
FROM insurance.claim;

SELECT status, count(*) AS claims,
       sum(estimated_amount) AS estimated_claim_amount
FROM insurance.claim
GROUP BY status
ORDER BY status;

-- The protection schedule must keep measured data loss and recovery duration
-- within the accepted RPO and RTO. Replace the teaching arrival rate with the
-- monitored peak rate before using the exposure estimate operationally.

\echo '\n-- Lab 7B: Capture a business validation baseline before backup'
SELECT lab_m7.capture_validation(:'snapshot') AS validation_run_id \gset

SELECT r.run_id, r.snapshot_name, r.captured_at, r.database_name,
       r.server_version, r.function_count, r.procedure_count,
       sum(t.row_count) AS total_rows
FROM lab_m7.validation_run AS r
JOIN lab_m7.table_validation AS t USING (run_id)
WHERE r.run_id = :validation_run_id
GROUP BY r.run_id
ORDER BY r.run_id;

SELECT schema_name, table_name, row_count,
       timestamp_column, min_timestamp, max_timestamp
FROM lab_m7.table_validation
WHERE run_id = :validation_run_id
ORDER BY schema_name, table_name;

SELECT claim_no, tenant_id, status, estimated_amount, created_at, updated_at
FROM insurance.claim
WHERE claim_no IN ('CLM-1001', 'CLM-2001', 'CLM-3001')
ORDER BY claim_no;

\echo '\n-- Lab 7C: Logical backup scope and artifact checks'
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
       c.reltuples::bigint AS estimated_rows
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname = 'insurance'
ORDER BY pg_total_relation_size(c.oid) DESC, c.relname;

SELECT count(*) FILTER (WHERE rolcanlogin) AS login_roles,
       count(*) FILTER (WHERE NOT rolcanlogin) AS group_roles,
       count(*) FILTER (WHERE rolsuper) AS superusers
FROM pg_roles;

SELECT extname, extversion
FROM pg_extension
ORDER BY extname;

\echo 'Create and inspect a custom-format ClaimSure backup from the host:'
\echo '  ./scripts/backup-logical.sh'
\echo '  DUMP_FILE=$(ls -t backup/claimsure-*.dump | head -1)'
\echo '  docker compose exec -T primary pg_restore --list < "$DUMP_FILE"'
\echo 'Capture globals separately because roles and tablespaces are not in pg_dump:'
\echo '  docker compose exec -T primary pg_dumpall -U postgres --globals-only > backup/globals.sql'

\echo '\n-- Lab 7D: Post-restore validation and difference report'
-- Run this section against claimsure_restore with snapshot=after_restore.
-- A baseline named before_backup must exist inside the restored dump.
SELECT current_database() <> 'claimsure' AS isolated_restore_database \gset
\if :isolated_restore_database
SELECT lab_m7.capture_validation(:'snapshot') AS restored_validation_run_id \gset

WITH chosen AS (
    SELECT DISTINCT ON (snapshot_name)
           run_id, snapshot_name, database_name, captured_at,
           function_count, procedure_count
    FROM lab_m7.validation_run
    WHERE snapshot_name IN ('before_backup', :'snapshot')
    ORDER BY snapshot_name, run_id DESC
), table_compare AS (
    SELECT t.schema_name, t.table_name,
           max(t.row_count) FILTER (WHERE c.snapshot_name = 'before_backup')
               AS before_rows,
           max(t.row_count) FILTER (WHERE c.snapshot_name = :'snapshot')
               AS restored_rows
    FROM chosen AS c
    JOIN lab_m7.table_validation AS t USING (run_id)
    GROUP BY t.schema_name, t.table_name
)
SELECT schema_name, table_name, before_rows, restored_rows,
       restored_rows - before_rows AS row_difference,
       CASE
           WHEN before_rows IS NULL OR restored_rows IS NULL THEN 'MISSING SNAPSHOT'
           WHEN before_rows = restored_rows THEN 'PASS'
           ELSE 'REVIEW'
       END AS result
FROM table_compare
ORDER BY result DESC, schema_name, table_name;

SELECT snapshot_name, database_name, captured_at,
       function_count, procedure_count
FROM lab_m7.validation_run
WHERE run_id IN (
    SELECT max(run_id)
    FROM lab_m7.validation_run
    WHERE snapshot_name IN ('before_backup', :'snapshot')
    GROUP BY snapshot_name
)
ORDER BY snapshot_name;
\else
\echo 'Lab 7D skipped: select an isolated database, for example:'
\echo '  TARGET_DATABASE=claimsure_restore ./scripts/run-module7-lab.sh lab07-D'
\endif

\echo 'Isolated logical restore commands:'
\echo '  docker compose exec -T primary dropdb -U postgres --if-exists claimsure_restore'
\echo '  docker compose exec -T primary createdb -U postgres -T template0 claimsure_restore'
\echo '  docker compose exec -T primary pg_restore -U postgres -d claimsure_restore --exit-on-error < "$DUMP_FILE"'
\echo 'The Module 7 runner performs these steps through restore-logical.sh.'

\echo '\n-- Lab 7E: Physical backup and WAL archive readiness'
SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name IN (
    'archive_mode', 'archive_command', 'wal_level', 'max_wal_senders',
    'max_replication_slots', 'wal_keep_size', 'full_page_writes',
    'data_checksums'
)
ORDER BY name;

SELECT archived_count, failed_count, last_archived_wal,
       last_archived_time, last_failed_wal, last_failed_time,
       stats_reset
FROM pg_stat_archiver;

SELECT slot_name, slot_type, active, restart_lsn,
       wal_status, safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;

SELECT num_timed, num_requested, num_done,
       buffers_written, write_time, sync_time, stats_reset
FROM pg_stat_checkpointer;

\echo 'Create and verify a physical base backup from the host:'
\echo '  ./scripts/backup-physical.sh'
\echo '  BASE=$(ls -dt backup/base_* | head -1)'
\echo '  docker compose exec -T primary pg_verifybackup "/backup/$(basename "$BASE")"'

\echo '\n-- Lab 7F: Named restore point and recovery boundary'
SELECT pg_is_in_recovery() AS is_replica \gset
\if :is_replica
\echo 'Run Lab 7F on the ClaimSure primary. A standby cannot create a restore point.'
\else
SELECT clock_timestamp() AS restore_point_time,
       :'restore_point' AS restore_point_name,
       pg_create_restore_point(:'restore_point') AS restore_point_lsn \gset

SELECT :'restore_point_name' AS restore_point_name,
       :'restore_point_lsn'::pg_lsn AS restore_point_lsn,
       pg_walfile_name(:'restore_point_lsn'::pg_lsn) AS required_wal_file,
       pg_current_wal_lsn() AS current_lsn;
\endif

SELECT archived_count, failed_count, last_archived_wal,
       last_archived_time, last_failed_wal, last_failed_time
FROM pg_stat_archiver;

\echo 'A PITR chain needs a base backup before the target and every required'
\echo 'WAL segment through the target. The Module 7 runner continues with:'
\echo '  PITR_PORT=15544 ./scripts/pitr-recover.sh'

\echo '\n-- Lab 7G: Recovery evidence and keep-or-fix decision'
SELECT o.service_name, o.rpo_minutes AS target_rpo_minutes,
       o.rto_minutes AS target_rto_minutes,
       e.exercise_name, e.artifact_uri, e.verification_method,
       e.result, e.measured_rpo_minutes, e.measured_rto_minutes,
       e.recorded_at, e.notes
FROM lab_m7.recovery_objective AS o
LEFT JOIN lab_m7.recovery_evidence AS e ON true
ORDER BY e.recorded_at DESC NULLS LAST;

\echo 'Record one row after an isolated restore drill, for example:'
\echo '  INSERT INTO lab_m7.recovery_evidence('
\echo '    exercise_name, artifact_uri, verification_method, result,'
\echo '    measured_rpo_minutes, measured_rto_minutes, notes)'
\echo '  VALUES ('
\echo '    ''monthly logical restore'', ''backup/claimsure-...dump'','
\echo '    ''row counts + claim samples + routine inventory'', ''PASS'','
\echo '    8, 24, ''restored into claimsure_restore'');'

SELECT snapshot_name, database_name, captured_at,
       function_count, procedure_count
FROM lab_m7.validation_run
ORDER BY run_id DESC
LIMIT 10;

\echo 'Recovery approval requires:'
\echo '1. Artifact integrity check passed'
\echo '2. Restore completed in an isolated compatible target'
\echo '3. Claim counts, timestamps, and sample claims match the expected point'
\echo '4. Measured RPO and RTO meet the ClaimSure objectives'
\echo '5. Owner recorded the result, exceptions, and next test date'

\timing off

\set ON_ERROR_STOP on
SELECT to_regnamespace('lab_m9_shell') IS NOT NULL AS has_schema \gset
\if :has_schema
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$ BEGIN
 IF to_regclass('lab_m9_shell.module_identity') IS NULL THEN
  RAISE EXCEPTION 'Unmarked schema; refusing Module 9 cleanup';
 END IF;
 IF (SELECT identity FROM lab_m9_shell.module_identity WHERE id=1) IS DISTINCT FROM 'module09-shell-v1' THEN
  RAISE EXCEPTION 'Invalid Module 9 marker';
 END IF;
END $$;
-- No CASCADE: unknown objects/dependencies cause rollback, preserving them.
DROP TABLE IF EXISTS lab_m9_shell.queue,lab_m9_shell.workload,lab_m9_shell.lock_demo,lab_m9_shell.module_identity;
DROP SCHEMA lab_m9_shell;
COMMIT;
\endif
\echo 'Module 9 fixtures removed. Database/pg_stat_statements counters and Prometheus/Grafana history are preserved.'

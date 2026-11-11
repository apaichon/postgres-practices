\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$
BEGIN
 IF current_setting('server_version_num')::int<180000 OR pg_is_in_recovery() THEN
  RAISE EXCEPTION 'Use a PostgreSQL 18+ primary';
 END IF;
 IF to_regnamespace('lab_m9_shell') IS NOT NULL AND to_regclass('lab_m9_shell.module_identity') IS NULL THEN
  RAISE EXCEPTION 'Existing lab_m9_shell has no Module 9 marker; preserving it';
 END IF;
 IF to_regnamespace('lab_m9_shell') IS NOT NULL THEN
  IF (SELECT nspowner FROM pg_namespace WHERE nspname='lab_m9_shell')<>(SELECT oid FROM pg_roles WHERE rolname=current_user) THEN
   RAISE EXCEPTION 'Module 9 schema belongs to another role';
  END IF;
  IF (SELECT identity FROM lab_m9_shell.module_identity WHERE id=1) IS DISTINCT FROM 'module09-shell-v1' THEN
   RAISE EXCEPTION 'Invalid Module 9 schema marker';
  END IF;
 END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS lab_m9_shell;
CREATE TABLE IF NOT EXISTS lab_m9_shell.module_identity(
 id int PRIMARY KEY CHECK(id=1), identity text NOT NULL CHECK(identity='module09-shell-v1')
);
INSERT INTO lab_m9_shell.module_identity VALUES (1,'module09-shell-v1') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m9_shell.lock_demo(id int PRIMARY KEY,note text NOT NULL);
CREATE TABLE IF NOT EXISTS lab_m9_shell.workload(id int PRIMARY KEY,bucket int,amount numeric(12,2),payload text);
CREATE TABLE IF NOT EXISTS lab_m9_shell.queue(id int PRIMARY KEY,touches int NOT NULL DEFAULT 0);
TRUNCATE lab_m9_shell.lock_demo,lab_m9_shell.workload,lab_m9_shell.queue;
INSERT INTO lab_m9_shell.lock_demo VALUES(1,'ready'),(2,'ready');
INSERT INTO lab_m9_shell.workload SELECT g,g%100,(g%50000)::numeric,repeat(md5(g::text),3) FROM generate_series(1,:rows) g;
INSERT INTO lab_m9_shell.queue SELECT g,0 FROM generate_series(1,1000) g;
ANALYZE lab_m9_shell.workload;
ANALYZE lab_m9_shell.queue;
COMMIT;
SELECT current_database() AS database,current_user AS login,count(*) AS rows FROM lab_m9_shell.workload;

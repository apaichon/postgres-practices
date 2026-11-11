\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_setting('server_version_num')::int < 180000 OR pg_is_in_recovery() THEN
  RAISE EXCEPTION 'Module 6 requires a PostgreSQL 18+ primary';
 END IF;
 IF to_regnamespace('lab_m6_shell') IS NOT NULL AND
    to_regclass('lab_m6_shell.module_identity') IS NULL THEN
  RAISE EXCEPTION 'Existing lab_m6_shell has no Module 6 shell marker; preserving it';
 END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS lab_m6_shell;
CREATE TABLE IF NOT EXISTS lab_m6_shell.module_identity (
 id int PRIMARY KEY CHECK(id=1), identity text NOT NULL CHECK(identity='module06-shell-v1')
);
INSERT INTO lab_m6_shell.module_identity VALUES (1,'module06-shell-v1') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m6_shell.report_workload (
 claim_id int PRIMARY KEY, claim_no text, branch_code text, status text,
 estimated_amount numeric(12,2), payload text
);
INSERT INTO lab_m6_shell.report_workload
SELECT g,'CLM-'||g, (ARRAY['BKK','CNX','HKT','KKN'])[1+g%4],
 (ARRAY['NEW','UNDER_REVIEW','APPROVED','PAID','CLOSED','REJECTED'])[1+g%6],
 5000+g%500000,repeat(md5(g::text),6)
FROM generate_series(1,:rows) g ON CONFLICT DO NOTHING;
ANALYZE lab_m6_shell.report_workload;
CREATE TABLE IF NOT EXISTS lab_m6_shell.capacity_probe(id int PRIMARY KEY, amount int);
INSERT INTO lab_m6_shell.capacity_probe VALUES (1,100) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m6_shell.queue (
 id int PRIMARY KEY, status text, payload text
);
INSERT INTO lab_m6_shell.queue
SELECT g,'NEW',repeat(md5(g::text),3) FROM generate_series(1,:rows) g ON CONFLICT DO NOTHING;
ANALYZE lab_m6_shell.queue;
CREATE TABLE IF NOT EXISTS lab_m6_shell.metrics (
 run_id text, lab text, phase text, iteration int, metric text,
 value numeric, unit text, details jsonb DEFAULT '{}',
 measured_at timestamptz DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS lab_m6_shell.queue_restore (
 id int PRIMARY KEY CHECK(id=1), original_options text[], pending boolean NOT NULL
);
CREATE OR REPLACE FUNCTION lab_m6_shell.restore_queue_options() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE original text[]; dirty boolean; opt text; key text;
BEGIN
 SELECT original_options,pending INTO original,dirty FROM lab_m6_shell.queue_restore WHERE id=1 FOR UPDATE;
 IF dirty IS DISTINCT FROM true THEN RETURN; END IF;
 ALTER TABLE lab_m6_shell.queue RESET (
  autovacuum_vacuum_threshold,autovacuum_vacuum_scale_factor,
  autovacuum_analyze_threshold,autovacuum_analyze_scale_factor,autovacuum_vacuum_insert_threshold);
 FOREACH opt IN ARRAY coalesce(original,ARRAY[]::text[]) LOOP
  key:=split_part(opt,'=',1);
  IF key IN ('autovacuum_vacuum_threshold','autovacuum_vacuum_scale_factor',
             'autovacuum_analyze_threshold','autovacuum_analyze_scale_factor','autovacuum_vacuum_insert_threshold') THEN
   EXECUTE format('ALTER TABLE lab_m6_shell.queue SET (%I=%L)',key,substr(opt,length(key)+2));
  END IF;
 END LOOP;
 UPDATE lab_m6_shell.queue_restore SET pending=false WHERE id=1;
END $$;
CREATE OR REPLACE FUNCTION lab_m6_shell.measure_sort(rid text, phase_name text, mem text, n int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE plan jsonb; node jsonb;
BEGIN
 PERFORM set_config('work_mem',mem,true);
 PERFORM set_config('max_parallel_workers_per_gather','0',true);
 EXECUTE $q$EXPLAIN (ANALYZE,BUFFERS,SETTINGS,FORMAT JSON)
 SELECT claim_no,branch_code,status,estimated_amount,payload
 FROM lab_m6_shell.report_workload WHERE status IN ('NEW','UNDER_REVIEW','APPROVED')
 ORDER BY branch_code,status,estimated_amount DESC,claim_no$q$ INTO plan;
 node:=plan->0->'Plan';
 INSERT INTO lab_m6_shell.metrics(run_id,lab,phase,iteration,metric,value,unit,details)
 SELECT rid,'B',phase_name,n,k,v,u,jsonb_build_object('work_mem',mem,'plan',plan,
   'sort_method',node->>'Sort Method','sort_space_type',node->>'Sort Space Type')
 FROM (VALUES ('execution_ms',(plan->0->>'Execution Time')::numeric,'ms'),
   ('temp_written',coalesce((node->>'Temp Written Blocks')::numeric,0),'blocks'),
   ('sort_space',coalesce((node->>'Sort Space Used')::numeric,0),'kB')) m(k,v,u);
END $$;
CREATE TABLE IF NOT EXISTS lab_m6_shell.wal_probe(id bigint PRIMARY KEY,payload text);
ALTER TABLE lab_m6_shell.wal_probe ALTER COLUMN payload SET STORAGE PLAIN;
CREATE OR REPLACE PROCEDURE lab_m6_shell.fill_wal(n int) LANGUAGE plpgsql AS $$
DECLARE batch int;
BEGIN
 FOR batch IN 0..((n-1)/5000) LOOP
  INSERT INTO lab_m6_shell.wal_probe
  SELECT g,repeat(md5(g::text),48)
  FROM generate_series(batch*5000+1,least(n,(batch+1)*5000)) g;
  COMMIT;
 END LOOP;
END $$;
SELECT current_database() AS database,current_user AS login,
 (SELECT count(*) FROM lab_m6_shell.report_workload) AS report_rows,
 (SELECT count(*) FROM lab_m6_shell.queue) AS queue_rows;

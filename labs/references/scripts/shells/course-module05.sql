\set ON_ERROR_STOP on
\echo 'Module 5A/B: own connections and available background statistics'
SELECT pg_backend_pid(),current_database(),current_user,pg_postmaster_start_time();
SELECT pid,backend_type,state,wait_event_type,wait_event FROM pg_stat_activity
WHERE usename=current_user OR backend_type<>'client backend' ORDER BY pid;
SELECT * FROM pg_stat_bgwriter;
SELECT * FROM pg_stat_checkpointer;
SELECT wal_records,wal_fpi,wal_bytes,wal_buffers_full FROM pg_stat_wal;
\echo 'Module 5C/D: locks, tuple versions, visibility; disposable rows only'
BEGIN;
SET LOCAL lock_timeout='5s';
SELECT ctid,xmin,xmax,* FROM lab_m5_shell.claim WHERE id=1;
UPDATE lab_m5_shell.claim SET amount=amount+1 WHERE id=1 RETURNING ctid,xmin,xmax,amount;
SELECT locktype,mode,granted FROM pg_locks WHERE pid=pg_backend_pid();
SAVEPOINT before_delete;
DELETE FROM lab_m5_shell.claim WHERE id=2;
SELECT count(*) AS invisible_after_delete FROM lab_m5_shell.claim WHERE id=2;
ROLLBACK TO SAVEPOINT before_delete;
SELECT count(*) AS visible_again FROM lab_m5_shell.claim WHERE id=2;
ROLLBACK;
\echo 'Module 5F: real committed WAL batch, then delete only this batch'
SELECT pg_current_wal_insert_lsn() AS start_lsn \gset
INSERT INTO lab_m5_shell.event(batch,payload) SELECT :'run_id',md5(g::text) FROM generate_series(1,1000) g;
SELECT pg_current_wal_insert_lsn() AS end_lsn \gset
SELECT pg_wal_lsn_diff(:'end_lsn',:'start_lsn') AS wal_bytes,
 count(*) AS committed_rows FROM lab_m5_shell.event WHERE batch=:'run_id';
DELETE FROM lab_m5_shell.event WHERE batch=:'run_id';
\echo 'Module 5G: relation mapping; no privileged filesystem access or checkpoint'
SELECT current_database(),(SELECT oid FROM pg_database WHERE datname=current_database()) AS database_oid,
 pg_relation_filenode('lab_m5_shell.claim'),pg_relation_filepath('lab_m5_shell.claim'),
 pg_relation_size('lab_m5_shell.claim') AS relation_bytes;

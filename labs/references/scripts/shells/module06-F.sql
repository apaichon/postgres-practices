\echo '6F: private server logs, identical sleep/sort/row-lock workload'
BEGIN;
SET LOCAL work_mem='64kB';
SET LOCAL max_parallel_workers_per_gather=0;
SET LOCAL lock_timeout='5s';
\if :candidate
SET LOCAL log_min_duration_statement='500ms';
SET LOCAL log_temp_files=0;
SET LOCAL log_lock_waits=on;
SET LOCAL deadlock_timeout='100ms';
\endif
SELECT name,current_setting(name),reset_val FROM pg_settings
WHERE name IN ('log_min_duration_statement','log_temp_files','log_lock_waits','deadlock_timeout');
SELECT pg_sleep(.6);
EXPLAIN (ANALYZE,BUFFERS)
SELECT claim_no,payload FROM lab_m6_shell.report_workload ORDER BY payload,claim_no;
UPDATE lab_m6_shell.capacity_probe SET amount=amount+1 WHERE id=1;
ROLLBACK;
SELECT name,current_setting(name),reset_val FROM pg_settings
WHERE name IN ('log_min_duration_statement','log_temp_files','log_lock_waits','deadlock_timeout');

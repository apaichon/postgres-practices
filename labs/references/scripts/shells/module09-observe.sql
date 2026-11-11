SELECT current_database() AS database,current_user AS login,current_setting('port') AS port;
SELECT pid,application_name,state,wait_event_type,wait_event,
 round(extract(epoch FROM clock_timestamp()-xact_start)::numeric,2) AS transaction_seconds,
 pg_blocking_pids(pid) AS blockers,left(query,120) AS query
FROM pg_stat_activity WHERE datname=current_database() AND usename=current_user
AND application_name LIKE 'module09\_%' ESCAPE '\' AND pid<>pg_backend_pid()
ORDER BY pid;
SELECT b.pid AS blocked_pid,h.pid AS blocker_pid,b.application_name AS blocked_application,
 h.application_name AS blocker_application,b.wait_event_type,b.wait_event
FROM pg_stat_activity b CROSS JOIN LATERAL unnest(pg_blocking_pids(b.pid)) p(pid)
JOIN pg_stat_activity h ON h.pid=p.pid
WHERE b.datname=current_database() AND b.usename=current_user
AND b.application_name LIKE 'module09\_%' ESCAPE '\';
SELECT datname,numbackends,xact_commit,xact_rollback,deadlocks,temp_files,temp_bytes
FROM pg_stat_database WHERE datname=current_database();
SELECT schemaname,relname,n_live_tup,n_dead_tup,autovacuum_count,last_autovacuum
FROM pg_stat_user_tables WHERE schemaname='lab_m9_shell' ORDER BY relname;
SELECT EXISTS(SELECT FROM pg_extension WHERE extname='pg_stat_statements') AS has_pgss \gset
\if :has_pgss
SELECT queryid,calls,round(total_exec_time::numeric,2) AS total_ms,
 round(mean_exec_time::numeric,2) AS mean_ms,rows,temp_blks_written,left(query,160) AS query
FROM pg_stat_statements WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database())
AND userid=(SELECT oid FROM pg_roles WHERE rolname=current_user)
AND query LIKE '%lab_m9_shell%' AND query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC LIMIT 15;
\endif

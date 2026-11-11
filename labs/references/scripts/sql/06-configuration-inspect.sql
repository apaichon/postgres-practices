-- LOGIN postgres on the dedicated claimsure_m6 instance. Read-only inspection.
\set ON_ERROR_STOP on
\pset pager off
SHOW config_file;
SHOW data_directory;
SELECT current_database(), current_user, pg_postmaster_start_time();
SELECT name, setting, unit, context, source, sourcefile, pending_restart
FROM pg_settings
WHERE name IN ('max_connections', 'shared_buffers', 'work_mem',
 'max_wal_size', 'checkpoint_timeout', 'random_page_cost',
 'max_worker_processes', 'max_parallel_workers', 'max_parallel_workers_per_gather',
 'autovacuum_vacuum_cost_limit', 'autovacuum_max_workers', 'autovacuum_worker_slots')
ORDER BY name;
SELECT sourcefile, sourceline, name, setting, applied, error
FROM pg_file_settings
WHERE error IS NOT NULL OR sourcefile LIKE '%module06%'
ORDER BY sourcefile, sourceline;

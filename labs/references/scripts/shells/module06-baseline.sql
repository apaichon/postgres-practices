SELECT name, current_setting(name) AS effective_value, setting, unit,
       boot_val AS postgres_boot_default, reset_val AS session_reset_value,
       context, source, sourcefile, sourceline, pending_restart
FROM pg_settings
WHERE name IN (
 'max_connections','reserved_connections','superuser_reserved_connections',
 'shared_buffers','work_mem','maintenance_work_mem','effective_cache_size',
 'max_parallel_workers_per_gather','statement_timeout','lock_timeout',
 'idle_in_transaction_session_timeout','max_wal_size','min_wal_size',
 'checkpoint_timeout','checkpoint_completion_target','wal_level',
 'fsync','full_page_writes','synchronous_commit','archive_mode',
 'autovacuum','autovacuum_naptime','autovacuum_vacuum_threshold',
 'autovacuum_vacuum_scale_factor','autovacuum_vacuum_max_threshold',
 'autovacuum_analyze_threshold','autovacuum_analyze_scale_factor',
 'log_min_duration_statement','log_temp_files','log_lock_waits',
 'deadlock_timeout','log_line_prefix','logging_collector','log_destination')
ORDER BY name;

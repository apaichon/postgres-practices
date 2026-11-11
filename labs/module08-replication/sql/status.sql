-- LOGIN: postgres in this private lab. Run on each node, never on classroom DB.
\pset pager off
SELECT current_setting('cluster_name') AS node,
       current_database() AS database_name, pg_is_in_recovery() AS is_standby,
       current_setting('transaction_read_only') AS read_only,
       (SELECT system_identifier FROM pg_control_system()) AS system_identifier;
SELECT application_name, state, sync_state, sent_lsn, flush_lsn, replay_lsn,
       write_lag, flush_lag, replay_lag,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_gap_bytes
FROM pg_stat_replication
WHERE NOT pg_is_in_recovery()
ORDER BY application_name;
SELECT status, sender_host, sender_port, slot_name, written_lsn, flushed_lsn,
       latest_end_lsn, last_msg_receipt_time
FROM pg_stat_wal_receiver;
SELECT slot_name, slot_type, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal,
       wal_status, safe_wal_size
FROM pg_replication_slots ORDER BY slot_name;
SELECT name, setting FROM pg_settings
WHERE name IN ('wal_level', 'max_wal_senders', 'max_replication_slots',
               'synchronous_commit', 'synchronous_standby_names') ORDER BY name;

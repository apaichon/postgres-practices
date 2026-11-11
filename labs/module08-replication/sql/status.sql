-- LOGIN: postgres in this private lab. Run on each node, never on classroom DB.
\pset pager off
SELECT current_setting('cluster_name') AS node,
       current_database() AS database_name, pg_is_in_recovery() AS is_standby,
       current_setting('transaction_read_only') AS read_only,
       (SELECT system_identifier FROM pg_control_system()) AS system_identifier;
SELECT application_name, state, sync_state, sent_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_gap_bytes
FROM pg_stat_replication
WHERE NOT pg_is_in_recovery()
ORDER BY application_name;
SELECT status, sender_host, sender_port, slot_name, written_lsn, flushed_lsn,
       latest_end_lsn, last_msg_receipt_time
FROM pg_stat_wal_receiver;
SELECT slot_name, active, restart_lsn, wal_status, safe_wal_size
FROM pg_replication_slots ORDER BY slot_name;

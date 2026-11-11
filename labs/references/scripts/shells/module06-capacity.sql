SELECT current_database() AS database,current_user AS login,
 current_setting('max_connections')::int AS cluster_connection_limit,
 (SELECT rolconnlimit FROM pg_roles WHERE rolname=current_user) AS role_connection_limit,
 count(*) AS own_client_sessions,
 count(*) FILTER(WHERE state='active') AS own_active,
 count(*) FILTER(WHERE state='idle') AS own_idle,
 count(*) FILTER(WHERE state LIKE 'idle in transaction%') AS own_idle_transactions,
 count(*) FILTER(WHERE wait_event_type='Lock') AS own_lock_waits
FROM pg_stat_activity
WHERE datname=current_database() AND usename=current_user AND backend_type='client backend';

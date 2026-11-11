\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 9 Blocking — Session B ==='

\echo 'Current holder of the lab row/table locks:'
SELECT l.pid AS holder_pid,
       l.mode,
       l.granted,
       a.state,
       left(a.query, 100) AS holder_query
FROM pg_locks l
JOIN pg_stat_activity a USING (pid)
WHERE l.relation = 'lab_m9.lock_demo'::regclass
ORDER BY l.granted DESC, l.pid;

SELECT blocked.pid AS blocked_pid,
       blocker.pid AS blocker_pid,
       blocked.wait_event_type,
       blocked.wait_event,
       left(blocker.query, 100) AS blocker_query
FROM pg_stat_activity blocked
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
JOIN pg_stat_activity blocker ON blocker.pid = b.blocker_pid;

SET lock_timeout = '2s';
\set ON_ERROR_STOP off
UPDATE lab_m9.lock_demo SET note = 'attempted by session B' WHERE id = 1;
\set ON_ERROR_STOP on
RESET lock_timeout;

SELECT pid, state, wait_event_type, wait_event, left(query, 100) AS query
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY pid;

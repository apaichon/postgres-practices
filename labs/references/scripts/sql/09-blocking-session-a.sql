\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 9 Blocking — Session A ==='
BEGIN;
UPDATE lab_m9.lock_demo SET note = 'locked by session A' WHERE id = 1;
SELECT pg_backend_pid() AS blocker_pid;
\echo 'Row lock is held. Start Session B now.'
\prompt 'After Session B shows the blocker, press Enter to COMMIT: ' continue
COMMIT;
SELECT * FROM lab_m9.lock_demo;

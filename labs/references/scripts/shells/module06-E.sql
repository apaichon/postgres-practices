-- Capture exactly the pre-test options before touching the lab queue.
SELECT lab_m6_shell.restore_queue_options();
INSERT INTO lab_m6_shell.queue_restore(id,original_options,pending)
SELECT 1,reloptions,true FROM pg_class WHERE oid='lab_m6_shell.queue'::regclass
ON CONFLICT(id) DO UPDATE SET original_options=excluded.original_options,pending=true;
-- Hold insert-triggered vacuum disabled in BOTH samples; the experiment
-- compares update/dead-tuple thresholds. The exact prior option is restored.
ALTER TABLE lab_m6_shell.queue SET (autovacuum_vacuum_insert_threshold=-1);
TRUNCATE lab_m6_shell.queue;
INSERT INTO lab_m6_shell.queue SELECT g,'NEW',repeat(md5(g::text),3) FROM generate_series(1,:rows) g;
-- Prepare a clean baseline BEFORE the measured update/candidate comparison.
-- This prevents the bulk insert from triggering an insert-driven autovacuum.
VACUUM (ANALYZE) lab_m6_shell.queue;
SELECT 'before' AS phase,reloptions AS original_table_overrides,
 coalesce((SELECT option_value FROM pg_options_to_table(reloptions) WHERE option_name='autovacuum_vacuum_threshold'),current_setting('autovacuum_vacuum_threshold')) AS base,
 coalesce((SELECT option_value FROM pg_options_to_table(reloptions) WHERE option_name='autovacuum_vacuum_scale_factor'),current_setting('autovacuum_vacuum_scale_factor')) AS scale,
 reltuples::bigint AS rows
FROM pg_class WHERE oid='lab_m6_shell.queue'::regclass;
UPDATE lab_m6_shell.queue SET status='UNDER_REVIEW' WHERE id<=least(5000,:rows);
SELECT pg_stat_force_next_flush();


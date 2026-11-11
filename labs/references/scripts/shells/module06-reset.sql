SELECT to_regclass('lab_m6_shell.queue_restore') IS NOT NULL AS has_restore_state \gset
\if :has_restore_state
SELECT lab_m6_shell.restore_queue_options();
SELECT reloptions AS restored_table_options FROM pg_class WHERE oid='lab_m6_shell.queue'::regclass;
\endif
\echo 'Session/role experiments used ROLLBACK or disconnected. Shared cluster settings were not changed.'

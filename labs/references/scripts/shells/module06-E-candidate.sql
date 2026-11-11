ALTER TABLE lab_m6_shell.queue SET (
 autovacuum_vacuum_threshold=500,autovacuum_analyze_threshold=500,
 autovacuum_analyze_scale_factor=0.01
);
SELECT format('ALTER TABLE lab_m6_shell.queue SET (autovacuum_vacuum_scale_factor=%s)',2500.0/:rows) \gexec
SELECT 'after_candidate' AS phase,reloptions FROM pg_class WHERE oid='lab_m6_shell.queue'::regclass;

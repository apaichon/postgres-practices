\echo '6D: private cluster only. Same logged workload at each max_wal_size.'
TRUNCATE lab_m6_shell.wal_probe;
CHECKPOINT;
SELECT pg_stat_clear_snapshot();
CREATE TEMP TABLE m6_checkpoint_before AS SELECT * FROM pg_stat_checkpointer;
SELECT clock_timestamp() AS started,pg_current_wal_insert_lsn() AS start_lsn \gset
CALL lab_m6_shell.fill_wal(:wal_rows);
SELECT clock_timestamp() AS finished,pg_current_wal_insert_lsn() AS end_lsn \gset
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1);
SELECT pg_stat_clear_snapshot();
INSERT INTO lab_m6_shell.metrics(run_id,lab,phase,iteration,metric,value,unit,details)
SELECT :'run_id','D',:'phase',1,k,v,u,jsonb_build_object('max_wal_size',current_setting('max_wal_size'),'rows',:wal_rows)
FROM (VALUES
 ('wal_generated',pg_wal_lsn_diff(:'end_lsn'::pg_lsn,:'start_lsn'::pg_lsn),'bytes'),
 ('execution_ms',extract(epoch FROM :'finished'::timestamptz-:'started'::timestamptz)*1000,'ms')) m(k,v,u);
INSERT INTO lab_m6_shell.metrics(run_id,lab,phase,iteration,metric,value,unit,details)
SELECT :'run_id','D',:'phase',1,k,v,u,jsonb_build_object('max_wal_size',current_setting('max_wal_size'))
FROM pg_stat_checkpointer c CROSS JOIN m6_checkpoint_before b
CROSS JOIN LATERAL (VALUES ('requested_checkpoints',(c.num_requested-b.num_requested)::numeric,'count'),
 ('completed_checkpoints',(c.num_done-b.num_done)::numeric,'count'),
 ('checkpoint_write_time',(c.write_time-b.write_time)::numeric,'ms')) m(k,v,u)
WHERE c.stats_reset IS NOT DISTINCT FROM b.stats_reset;
SELECT phase,metric,round(value,3),unit,details FROM lab_m6_shell.metrics
WHERE run_id=:'run_id' AND lab='D' ORDER BY measured_at;

SELECT clock_timestamp() AS started \gset
BEGIN;
SELECT set_config(:'timeout_name',:'timeout_value',true);
-- SET LOCAL scope; the following workload is a separate protocol statement.
\set ON_ERROR_STOP off
\if :statement_test
SELECT pg_sleep(0.4);
\else
UPDATE lab_m6_shell.capacity_probe SET amount=amount+1 WHERE id=1;
\endif
\set observed_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK;
INSERT INTO lab_m6_shell.metrics(run_id,lab,phase,iteration,metric,value,unit,details)
VALUES (:'run_id','C',:'phase',1,:'timeout_name',
 extract(epoch FROM clock_timestamp()-:'started'::timestamptz)*1000,'ms',
 jsonb_build_object('sqlstate',:'observed_state','tested_value',:'timeout_value'));
SELECT :'phase' AS phase,:'timeout_name' AS parameter,:'timeout_value' AS tested_value,:'observed_state' AS sqlstate;
\if :expect_cancel
SELECT :'observed_state'=:'expected_state' AS expected_error_seen \gset
\if :expected_error_seen
\echo 'Expected timeout observed; ROLLBACK restored the original setting and row.'
\else
\echo 'ERROR: workload did not produce the expected timeout'
\quit 1
\endif
\endif

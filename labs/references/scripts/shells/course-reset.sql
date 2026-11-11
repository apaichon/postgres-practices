\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
-- RESTRICT throughout: outside dependencies/unknown objects prevent the reset.
DROP PROCEDURE IF EXISTS insurance.review_claim(text,numeric);
DROP FUNCTION IF EXISTS insurance.claims_by_status(text);
DROP VIEW IF EXISTS insurance.claim_detail_v;
DROP FUNCTION IF EXISTS insurance.claim_tax(numeric,numeric,numeric);
DROP MATERIALIZED VIEW IF EXISTS insurance.monthly_claim_summary;
DROP TABLE IF EXISTS insurance.claim_dashboard_snapshot,insurance.claim_report,insurance.claim_perf;
DROP TABLE IF EXISTS insurance.claim;
DROP TABLE IF EXISTS insurance.policy;
DROP TABLE IF EXISTS insurance.customer;
DROP SCHEMA IF EXISTS insurance;
DROP TABLE IF EXISTS lab_m4_shell.claim_audit,lab_m4_shell.claim_secure,lab_m4_shell.course_identity;
DROP SCHEMA IF EXISTS lab_m4_shell;
DROP TABLE IF EXISTS lab_m5_shell.event,lab_m5_shell.claim,lab_m5_shell.course_identity;
DROP SCHEMA IF EXISTS lab_m5_shell;
DROP FUNCTION IF EXISTS lab_m6_shell.measure_sort(text,text,text,int);
DROP PROCEDURE IF EXISTS lab_m6_shell.fill_wal(int);
DROP FUNCTION IF EXISTS lab_m6_shell.restore_queue_options();
DROP TABLE IF EXISTS lab_m6_shell.metrics,lab_m6_shell.wal_probe,lab_m6_shell.queue_restore,
 lab_m6_shell.queue,lab_m6_shell.capacity_probe,lab_m6_shell.report_workload,lab_m6_shell.module_identity;
DROP SCHEMA IF EXISTS lab_m6_shell;
\if :preflight
ROLLBACK;
\echo 'Reset dependency preflight passed; committed state unchanged.'
\else
COMMIT;
\echo 'Course schemas reset. Monitoring history, modules 8/10 and unknown schemas are not targeted.'
\endif

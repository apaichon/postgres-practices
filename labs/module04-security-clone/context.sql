-- Shared instructor context. psql variables are quoted as values/identifiers.
\set ON_ERROR_STOP on
\pset pager off
\if :{?student_no}
\else
  \echo 'Set student_no to your assigned two-digit number (01-20).'
  DO $$ BEGIN RAISE EXCEPTION 'Lab prerequisite or confirmation failed; see the message above.'; END $$;
\endif
SELECT :'student_no' ~ '^(0[1-9]|1[0-9]|20)$'
       AND current_database() = 'claimsure_' || :'student_no'
       AND current_setting('server_version_num')::integer >= 180000
       AND (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS correct_target
\gset
\if :correct_target
\else
  \echo 'Use PostgreSQL 18+, instructor superuser, matching claimsure_xx and student_no.'
  DO $$ BEGIN RAISE EXCEPTION 'Lab prerequisite or confirmation failed; see the message above.'; END $$;
\endif
SELECT 'lab_m4_clone_' || :'student_no' AS lab_schema,
       'm4c_owner_' || :'student_no' AS owner_role,
       'm4c_reader_' || :'student_no' AS reader_role,
       'm4c_writer_' || :'student_no' AS writer_role,
       'm4c_approver_' || :'student_no' AS approver_role,
       'm4c_auditor_' || :'student_no' AS auditor_role,
       'm4c_read_a_' || :'student_no' AS read_a,
       'm4c_read_b_' || :'student_no' AS read_b,
       'm4c_create_a_' || :'student_no' AS create_a,
       'm4c_approve_a_' || :'student_no' AS approve_a,
       'm4c_audit_' || :'student_no' AS audit_login
\gset

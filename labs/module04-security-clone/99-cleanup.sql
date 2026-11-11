\ir context.sql
\if :{?confirm_cleanup}
\else
  \echo 'Cleanup is optional. Set confirm_cleanup=lab_m4_clone_xx to discard only this lab.'
  DO $$ BEGIN RAISE EXCEPTION 'Lab prerequisite or confirmation failed; see the message above.'; END $$;
\endif
SELECT :'confirm_cleanup' = :'lab_schema'
       AND obj_description(to_regnamespace(:'lab_schema'), 'pg_namespace') = 'module04-security-clone-v1'
       AND (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = :'lab_schema') = :'owner_role'
       AS confirmed
\gset
\if :confirmed
\else
  \echo 'Schema name, lab marker and owner must match; refusing cleanup.'
  DO $$ BEGIN RAISE EXCEPTION 'Lab prerequisite or confirmation failed; see the message above.'; END $$;
\endif
-- Close the five application sessions before cleanup. No DROP OWNED is used.
BEGIN;
DROP SCHEMA :"lab_schema" CASCADE;
SELECT format('REVOKE CONNECT ON DATABASE %I FROM %I, %I, %I, %I, %I',
              current_database(), :'read_a', :'read_b', :'create_a', :'approve_a', :'audit_login')
\gexec
DROP ROLE :"read_a", :"read_b", :"create_a", :"approve_a", :"audit_login";
DROP ROLE :"writer_role", :"approver_role", :"auditor_role", :"reader_role", :"owner_role";
COMMIT;
\echo 'Removed only the clone schema and its dedicated lab roles. Source claimsure remains.'

\ir context.sql

-- Stop before changing anything if any name is already in use.
SELECT NOT EXISTS (
  SELECT FROM pg_roles WHERE rolname IN (
    :'owner_role', :'reader_role', :'writer_role', :'approver_role', :'auditor_role',
    :'read_a', :'read_b', :'create_a', :'approve_a', :'audit_login'
  )
) AND to_regnamespace(:'lab_schema') IS NULL AS fresh_names
\gset
\if :fresh_names
\else
  \echo 'Lab schema/roles already exist. Keep them for inspection or use the explicit cleanup first.'
  DO $$ BEGIN RAISE EXCEPTION 'Lab prerequisite or confirmation failed; see the message above.'; END $$;
\endif

BEGIN;
CREATE ROLE :"owner_role" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE :"reader_role" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE :"writer_role" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE :"approver_role" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE :"auditor_role" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE :"read_a" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;
CREATE ROLE :"read_b" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;
CREATE ROLE :"create_a" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;
CREATE ROLE :"approve_a" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;
CREATE ROLE :"audit_login" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;

GRANT :"reader_role" TO :"writer_role", :"approver_role" WITH INHERIT TRUE, SET FALSE;
GRANT :"reader_role" TO :"read_a", :"read_b" WITH INHERIT TRUE, SET FALSE;
GRANT :"writer_role" TO :"create_a" WITH INHERIT TRUE, SET FALSE;
GRANT :"approver_role" TO :"approve_a" WITH INHERIT TRUE, SET FALSE;
GRANT :"auditor_role" TO :"audit_login" WITH INHERIT TRUE, SET FALSE;
SELECT format('GRANT CONNECT ON DATABASE %I TO %I, %I, %I, %I, %I',
              current_database(), :'read_a', :'read_b', :'create_a', :'approve_a', :'audit_login')
\gexec
COMMIT;
\echo 'Created five groups and five logins without credentials. Set login passwords with psql \password before TCP tests.'

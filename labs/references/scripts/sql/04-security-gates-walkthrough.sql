\set ON_ERROR_STOP on
\pset pager off
\pset null '(null)'
\echo '=== Security gates: one claim question at a time ==='

-- Read this file from top to bottom. Each step asks one question, shows the
-- gate closed, opens it with one grant, then shows what is still closed.
--
--   1 User          CREATE ROLE. A name is not a privilege.
--   2 Connection    GRANT CONNECT. Login is not table access.
--   3 Schema        GRANT USAGE. Looking up a name is not reading a row.
--   4 Table         GRANT SELECT. Reading is not writing.
--   5 Operation     INSERT, direct nextval(), UPDATE, DELETE, and TRUNCATE
--                   are separate. An identity INSERT does not need sequence USAGE.
--   6 Column        SELECT and UPDATE can name columns.
--   7 Row           A policy limits which rows those privileges can touch.
--   8 Maintenance   GRANT MAINTAIN on one table. It is not data access.
--   9 Statistics    pg_stats follows column privileges and active row security.
--                   pg_stat_user_tables counts the whole table.
--
-- Cast, for student xx. Every name ends with the student number.
--
--   gate_owner_xx     NOLOGIN. Owns schema lab_gate_xx and its tables.
--   gate_staff_xx     NOLOGIN group. Receives the application privileges.
--   gate_app_xx       LOGIN. Inherits gate_staff_xx. The claims application.
--   gate_auditor_xx   LOGIN. Reads policyholder names, not email or phone.
--   gate_dba_xx       LOGIN. ANALYZE on claim only.
--
-- This file does not replace scripts/sql/04-security-user-management.sql.
-- It uses its own roles and schema, so both labs can exist for one student.
-- It does not change the insurance or public schema, and it does not grant
-- pg_monitor, pg_read_all_stats, pg_maintain, or any superuser attribute.
--
-- PostgreSQL 18. From the postgres-admin-labs directory:
--   psql -X -h HOST -p PORT -U postgres -d claimsure_xx \
--     -v student_no=xx -f scripts/sql/04-security-gates-walkthrough.sql
-- Already connected as the administrator:
--   \set student_no xx
--   \i scripts/sql/04-security-gates-walkthrough.sql
-- Pause before each step:
--   \set step_by_step on
--   \i scripts/sql/04-security-gates-walkthrough.sql
-- Remove only this walkthrough:
--   \set student_no xx
--   \i scripts/sql/04-security-gates-walkthrough-reset.sql
--
-- SET LOCAL ROLE changes whose privileges are checked. session_user stays
-- postgres, so this file does not test the password or pg_hba.conf.
-- After a stopped run: ROLLBACK; RESET ROLE;
-- A full rerun closes each gate again before opening it, so the denials
-- still appear the second time. Sample writes are rolled back. The three
-- seed claims remain.

\if :{?step_by_step}
\else
\set step_by_step off
\endif
SELECT lower(:'step_by_step') IN ('on', 'true', '1') AS guided_mode \gset

-- Denial shape used in every step:
--   BEGIN; SET LOCAL ROLE ...; SAVEPOINT gate;
--   stop-on-error off; statement that must fail; record SQLSTATE;
--   ROLLBACK TO SAVEPOINT gate; require 42501; ROLLBACK.
-- 42501 is insufficient_privilege. A row-policy refusal uses it too.

\if :{?student_no}
\else
DO $$ BEGIN RAISE EXCEPTION 'Missing student_no. Use -v student_no=xx (01..20).'; END $$;
\endif
SELECT :'student_no' ~ '^(0[1-9]|1[0-9]|20)$' AS valid_student \gset
\if :valid_student
\else
DO $$ BEGIN RAISE EXCEPTION 'student_no must be 01..20.'; END $$;
\endif
SELECT current_database() AS lab_database,
       session_user AS login_user,
       current_user AS effective_user,
       current_database() = 'claimsure_' || :'student_no' AS correct_database,
       current_setting('server_version_num')::int >= 180000 AS correct_version,
       current_user = session_user AND rolsuper AS administrator
FROM pg_roles WHERE rolname = current_user \gset
\if :correct_database
\else
DO $$ BEGIN RAISE EXCEPTION 'Connect to claimsure_xx matching student_no first.'; END $$;
\endif
\if :correct_version
\else
DO $$ BEGIN RAISE EXCEPTION 'This walkthrough requires PostgreSQL 18 or later.'; END $$;
\endif
\if :administrator
\else
\echo 'STOP: login is' :login_user '| effective role is' :effective_user
\echo 'ROLLBACK; then \connect' :lab_database 'postgres'
DO $$ BEGIN RAISE EXCEPTION 'Run this walkthrough as the lab superuser (normally postgres).'; END $$;
\endif
SELECT 'lab_gate_' || :'student_no' AS lab_schema,
       'gate_owner_' || :'student_no' AS owner_role,
       'gate_staff_' || :'student_no' AS staff_role,
       'gate_app_' || :'student_no' AS app_role,
       'gate_auditor_' || :'student_no' AS auditor_role,
       'gate_dba_' || :'student_no' AS dba_role,
       'Security gates lab ' || :'student_no' AS role_marker
\gset
SET lock_timeout = '5s';
\echo 'Student' :student_no '| Database' :lab_database '| Schema' :lab_schema
\echo 'App' :app_role '| inherits' :staff_role '| owner' :owner_role


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 1 — USER'
\echo 'Question: who are the identities, before any privilege exists?'
\echo 'The owner and the staff group cannot log in.'
\echo 'The app, auditor, and DBA can log in and inherit grants.'
\echo 'None of them is superuser, CREATEROLE, or BYPASSRLS.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 1 (Ctrl+C to stop): ' gate_continue
\endif
SELECT NOT EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                                :'auditor_role', :'dba_role'])
      AND shobj_description(oid, 'pg_authid') IS DISTINCT FROM :'role_marker'
) AS safe_role_names \gset
\if :safe_role_names
\else
DO $$ BEGIN RAISE EXCEPTION 'A gate_* role for this student exists outside this walkthrough. Reset was not run. Ask the instructor before changing it.'; END $$;
\endif
SELECT format('CREATE ROLE %I NOLOGIN', :'owner_role')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'owner_role')
\gexec
SELECT format('CREATE ROLE %I NOLOGIN', :'staff_role')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'staff_role')
\gexec
SELECT format('CREATE ROLE %I LOGIN INHERIT', :'app_role')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_role')
\gexec
SELECT format('CREATE ROLE %I LOGIN INHERIT', :'auditor_role')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'auditor_role')
\gexec
SELECT format('CREATE ROLE %I LOGIN INHERIT', :'dba_role')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'dba_role')
\gexec
ALTER ROLE :"owner_role" WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE :"staff_role" WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE :"app_role" WITH LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE :"auditor_role" WITH LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE :"dba_role" WITH LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
SELECT format('COMMENT ON ROLE %I IS %L', rolname, :'role_marker')
FROM pg_roles
WHERE rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                            :'auditor_role', :'dba_role'])
\gexec
-- Membership does not copy privileges that the group does not have yet.
GRANT :"staff_role" TO :"app_role"
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
SELECT rolname, rolcanlogin, rolinherit, rolsuper, rolcreaterole, rolbypassrls
FROM pg_roles
WHERE shobj_description(oid, 'pg_authid') = :'role_marker'
ORDER BY rolname;
SELECT r.rolname AS group_role, m.rolname AS member,
       am.inherit_option, am.set_option, am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname = :'app_role';
\echo 'PASS: five roles exist. Only the app inherits the staff group. No privileged attribute is on.'
\echo 'A LOGIN role still has no password. Later, the administrator can run \password' :app_role
\echo 'and open a second psql session. SET ROLE in this file is not that test.'


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 2 — CONNECTION'
\echo 'Question: may this identity start a session in this database?'
\echo 'Mechanism: GRANT CONNECT ON DATABASE.'
\echo 'Still closed after this step: schema USAGE.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 2 (Ctrl+C to stop): ' gate_continue
\endif
-- Take the explicit grant away, then look at PUBLIC. This shared classroom
-- database grants CONNECT to PUBLIC. Revoking it here would lock every
-- student out, so the script never does that.
REVOKE CONNECT ON DATABASE :"lab_database"
FROM :"app_role", :"auditor_role", :"dba_role";
SELECT has_database_privilege(:'app_role', :'lab_database', 'CONNECT') AS app_connect_before_grant,
       has_database_privilege('public', :'lab_database', 'CONNECT') AS public_connect
\gset
\echo 'App CONNECT before the explicit grant:' :app_connect_before_grant
\echo 'PUBLIC CONNECT:' :public_connect
\if :public_connect
\echo 'PUBLIC already opens connection for every role in this database.'
\echo 'The GRANT below records the three logins on purpose. It is not table access.'
\else
\echo 'PUBLIC cannot connect. The GRANT below is what lets these logins in.'
\endif
GRANT CONNECT ON DATABASE :"lab_database"
TO :"app_role", :"auditor_role", :"dba_role";
SELECT has_database_privilege(:'app_role', :'lab_database', 'CONNECT') AS app_can_connect \gset
\if :app_can_connect
\echo 'PASS: the app may connect to' :lab_database
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: GRANT CONNECT did not give the app CONNECT.'; END $$;
\endif
BEGIN;
SET LOCAL ROLE :"app_role";
SELECT session_user AS login_user, current_user AS effective_role;
\echo 'login_user stays postgres. current_user is the app. Password was not tested.'
ROLLBACK;


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 3 — SCHEMA'
\echo 'Question: may the app resolve objects in its lab schema?'
\echo 'Mechanism: the owner grants USAGE. The administrator does not own this schema.'
\echo 'Still closed after this step: CREATE in the schema, and SELECT on a table.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 3 (Ctrl+C to stop): ' gate_continue
\endif
SELECT pg_has_role(session_user, :'owner_role', 'SET') AS can_set_owner \gset
\if :can_set_owner
\else
DO $$ BEGIN RAISE EXCEPTION 'Cannot SET ROLE to the lab owner. Reconnect as the administrator.'; END $$;
\endif
SELECT NOT EXISTS (
    SELECT 1 FROM pg_namespace
    WHERE nspname = :'lab_schema'
      AND pg_get_userbyid(nspowner) IS DISTINCT FROM :'owner_role'
) AS schema_owner_ok \gset
\if :schema_owner_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'lab_gate_xx exists with an unexpected owner. This walkthrough stopped before changing it.'; END $$;
\endif
BEGIN;
CREATE SCHEMA IF NOT EXISTS :"lab_schema" AUTHORIZATION :"owner_role";
SET LOCAL ROLE :"owner_role";
REVOKE ALL ON SCHEMA :"lab_schema" FROM PUBLIC;
REVOKE USAGE, CREATE ON SCHEMA :"lab_schema"
FROM :"staff_role", :"auditor_role", :"dba_role";
COMMIT;
BEGIN;
SET LOCAL ROLE :"app_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
SELECT count(*) FROM :"lab_schema".claim;
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: without USAGE the app cannot resolve objects in the schema (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected schema permission denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"owner_role";
GRANT USAGE ON SCHEMA :"lab_schema" TO :"staff_role";
COMMIT;
SELECT has_schema_privilege(:'app_role', :'lab_schema', 'USAGE') AS app_can_resolve,
       has_schema_privilege(:'app_role', :'lab_schema', 'CREATE') AS app_can_create_object
\gset
\if :app_can_resolve
\echo 'PASS: the app inherits schema USAGE from the staff group.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: staff USAGE did not reach the app.'; END $$;
\endif
\if :app_can_create_object
DO $$ BEGIN RAISE EXCEPTION 'FAIL: USAGE must not include CREATE.'; END $$;
\else
\echo 'PASS: schema CREATE is still closed.'
\endif
BEGIN;
SET LOCAL ROLE :"app_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
CREATE TABLE :"lab_schema".not_allowed (id integer);
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: the app can look names up and still cannot create a table (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected schema CREATE denial 42501.'; END $$;
\endif
ROLLBACK;


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 4 — TABLE'
\echo 'Question: may the app read claims?'
\echo 'Mechanism: the owner grants SELECT on the table to the staff group.'
\echo 'Still closed after this step: INSERT.'
\echo 'Seed: tenant 101 has SEC-101-001 and SEC-101-002. Tenant 202 has SEC-202-001.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 4 (Ctrl+C to stop): ' gate_continue
\endif
BEGIN;
SET LOCAL ROLE :"owner_role";
CREATE TABLE IF NOT EXISTS :"lab_schema".claim (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    claim_no text NOT NULL UNIQUE,
    status text NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
-- A rerun returns to the pre-policy lesson. Step 7 turns row security back on.
ALTER TABLE :"lab_schema".claim DISABLE ROW LEVEL SECURITY;
ALTER TABLE :"lab_schema".claim NO FORCE ROW LEVEL SECURITY;
DELETE FROM :"lab_schema".claim WHERE claim_no LIKE 'SEC-STEP%';
INSERT INTO :"lab_schema".claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-101-001', 'NEW', 10000),
       (101, 'SEC-101-002', 'UNDER_REVIEW', 25000),
       (202, 'SEC-202-001', 'NEW', 18000)
ON CONFLICT (claim_no) DO NOTHING;
REVOKE ALL ON ALL TABLES IN SCHEMA :"lab_schema" FROM PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE
ON :"lab_schema".claim FROM :"staff_role";
COMMIT;
SELECT pg_get_serial_sequence(format('%I.claim', :'lab_schema'), 'claim_id') AS claim_id_seq,
       pg_get_serial_sequence(format('%I.claim', :'lab_schema'), 'claim_id') IS NOT NULL AS has_identity
\gset
\if :has_identity
\echo 'Identity sequence:' :claim_id_seq
\else
DO $$ BEGIN RAISE EXCEPTION 'claim.claim_id has no identity sequence.'; END $$;
\endif
BEGIN;
SET LOCAL ROLE :"app_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
SELECT claim_no FROM :"lab_schema".claim;
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: schema USAGE is open and table SELECT is still closed (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected table SELECT denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"owner_role";
GRANT SELECT ON :"lab_schema".claim TO :"staff_role";
COMMIT;
BEGIN;
SET LOCAL ROLE :"app_role";
SELECT claim_no, tenant_id, status, estimated_amount
FROM :"lab_schema".claim
ORDER BY claim_no;
SELECT coalesce(array_agg(claim_no ORDER BY claim_no)
                = ARRAY['SEC-101-001', 'SEC-101-002', 'SEC-202-001'], false) AS sees_all_three
FROM :"lab_schema".claim \gset
\if :sees_all_three
\echo 'PASS: SELECT shows both tenants. Row security is not on yet.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected the three seed claims.'; END $$;
\endif
ROLLBACK;
SELECT has_table_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'INSERT') AS app_can_insert \gset
\if :app_can_insert
DO $$ BEGIN RAISE EXCEPTION 'FAIL: SELECT must not include INSERT.'; END $$;
\else
\echo 'PASS: INSERT is still closed.'
\endif


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 5 — OPERATION'
\echo 'Question: which commands may the app run on the whole table?'
\echo 'SELECT is already open. INSERT, nextval(), UPDATE, DELETE, and'
\echo 'TRUNCATE are separate. Identity INSERT does not need sequence USAGE.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 5 (Ctrl+C to stop): ' gate_continue
\endif
BEGIN;
SET LOCAL ROLE :"owner_role";
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON :"lab_schema".claim FROM :"staff_role";
REVOKE UPDATE (claim_id, tenant_id, claim_no, status, estimated_amount, updated_at)
ON :"lab_schema".claim FROM :"staff_role";
COMMIT;
SELECT format('REVOKE ALL ON SEQUENCE %s FROM %I', :'claim_id_seq', :'staff_role') \gexec
BEGIN;
SET LOCAL ROLE :"app_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
INSERT INTO :"lab_schema".claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP5-TEMP', 'NEW', 500);
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: INSERT is closed (42501). The error names the table.'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected INSERT denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"owner_role";
GRANT INSERT ON :"lab_schema".claim TO :"staff_role";
COMMIT;
-- An identity column draws its value as the table owner.
-- Table INSERT is enough. A serial column would also need sequence USAGE.
-- Calling nextval() yourself is a separate gate, tested next.
BEGIN;
SET LOCAL ROLE :"app_role";
INSERT INTO :"lab_schema".claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP5-TEMP', 'NEW', 500)
RETURNING claim_no, tenant_id, status;
\echo 'PASS: INSERT works without a grant on the identity sequence. It will roll back.'
SAVEPOINT gate;
\set ON_ERROR_STOP off
SELECT nextval(:'claim_id_seq');
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: direct nextval() is still closed (42501). The error names the sequence.'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected sequence USAGE denial 42501 for nextval().'; END $$;
\endif
ROLLBACK;
\echo 'The temporary claim was rolled back. The three seed claims remain.'
SELECT format('GRANT USAGE ON SEQUENCE %s TO %I', :'claim_id_seq', :'staff_role') AS sequence_grant;
SELECT format('GRANT USAGE ON SEQUENCE %s TO %I', :'claim_id_seq', :'staff_role') \gexec
BEGIN;
SET LOCAL ROLE :"app_role";
SELECT nextval(:'claim_id_seq') AS sequence_value_after_usage_grant;
\echo 'PASS: sequence USAGE lets the app call nextval(). nextval is not rolled back.'
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"app_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
DELETE FROM :"lab_schema".claim WHERE claim_no = 'SEC-101-001';
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: DELETE is closed (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected DELETE denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"app_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
TRUNCATE :"lab_schema".claim;
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: TRUNCATE is closed (42501). It is not DELETE, and row security does not filter it.'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected TRUNCATE denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"owner_role";
GRANT UPDATE ON :"lab_schema".claim TO :"staff_role";
COMMIT;
BEGIN;
SET LOCAL ROLE :"app_role";
UPDATE :"lab_schema".claim
SET estimated_amount = estimated_amount + 1,
    updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, estimated_amount;
\echo 'PASS: table UPDATE can change the amount. Step 6 narrows this.'
ROLLBACK;


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 6 — COLUMN'
\echo 'Question: which columns may each identity use?'
\echo 'The auditor reads policyholder names. Email and phone stay closed.'
\echo 'The app keeps UPDATE on status and updated_at. The amount closes.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 6 (Ctrl+C to stop): ' gate_continue
\endif
BEGIN;
SET LOCAL ROLE :"owner_role";
CREATE TABLE IF NOT EXISTS :"lab_schema".policyholder (
    policyholder_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    UNIQUE (tenant_id, email)
);
INSERT INTO :"lab_schema".policyholder (tenant_id, full_name, email, phone)
VALUES (101, 'Demo Policyholder', 'demo@example.invalid', '000-000-0000')
ON CONFLICT (tenant_id, email) DO NOTHING;
REVOKE ALL ON :"lab_schema".policyholder FROM PUBLIC;
GRANT USAGE ON SCHEMA :"lab_schema" TO :"auditor_role";
REVOKE SELECT ON :"lab_schema".policyholder FROM :"auditor_role";
REVOKE SELECT (policyholder_id, tenant_id, full_name, email, phone)
ON :"lab_schema".policyholder FROM :"auditor_role";
GRANT SELECT (policyholder_id, tenant_id, full_name)
ON :"lab_schema".policyholder TO :"auditor_role";
REVOKE UPDATE ON :"lab_schema".claim FROM :"staff_role";
REVOKE UPDATE (claim_id, tenant_id, claim_no, status, estimated_amount, updated_at)
ON :"lab_schema".claim FROM :"staff_role";
GRANT UPDATE (status, updated_at) ON :"lab_schema".claim TO :"staff_role";
COMMIT;
SELECT has_column_privilege(:'auditor_role', format('%I.policyholder', :'lab_schema'),
                            'full_name', 'SELECT') AS auditor_name,
       has_column_privilege(:'auditor_role', format('%I.policyholder', :'lab_schema'),
                            'email', 'SELECT') AS auditor_email,
       has_column_privilege(:'app_role', format('%I.claim', :'lab_schema'),
                            'status', 'UPDATE') AS app_status,
       has_column_privilege(:'app_role', format('%I.claim', :'lab_schema'),
                            'estimated_amount', 'UPDATE') AS app_amount
\gset
\echo 'Auditor full_name SELECT:' :auditor_name '| email SELECT:' :auditor_email
\echo 'App status UPDATE:' :app_status '| amount UPDATE:' :app_amount
BEGIN;
SET LOCAL ROLE :"auditor_role";
SELECT policyholder_id, tenant_id, full_name
FROM :"lab_schema".policyholder
ORDER BY policyholder_id;
SAVEPOINT gate;
\set ON_ERROR_STOP off
SELECT email, phone FROM :"lab_schema".policyholder;
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: the auditor reads the name and cannot read email or phone (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected contact-column denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"app_role";
UPDATE :"lab_schema".claim
SET status = 'APPROVED', updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, status;
\echo 'PASS: status UPDATE is allowed. This change rolls back.'
SAVEPOINT gate;
\set ON_ERROR_STOP off
UPDATE :"lab_schema".claim
SET estimated_amount = 1
WHERE claim_no = 'SEC-101-001';
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: estimated_amount UPDATE is closed (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected amount-column denial 42501.'; END $$;
\endif
ROLLBACK;


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 7 — ROW'
\echo 'Question: which rows may the app see or write?'
\echo 'Mechanism: ENABLE and FORCE row level security, then one policy.'
\echo 'The policy compares tenant_id with the setting app.tenant_id.'
\echo 'FORCE makes the table owner subject to the policy too.'
\echo 'postgres still bypasses it, because this session is superuser.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 7 (Ctrl+C to stop): ' gate_continue
\endif
BEGIN;
SET LOCAL ROLE :"owner_role";
ALTER TABLE :"lab_schema".claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE :"lab_schema".claim FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS claim_tenant ON :"lab_schema".claim;
CREATE POLICY claim_tenant ON :"lab_schema".claim
TO :"staff_role"
USING (tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint)
WITH CHECK (tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint);
COMMIT;
\echo 'The app must set app.tenant_id only after the application has authorized that tenant.'
\echo 'A SQL user who can run SET can put any tenant id in that setting.'
BEGIN;
SET LOCAL ROLE :"app_role";
SELECT set_config('app.tenant_id', '101', true);
SELECT current_user AS effective_role,
       row_security_active(format('%I.claim', :'lab_schema')::regclass) AS row_policy_applies;
SELECT claim_no, tenant_id FROM :"lab_schema".claim ORDER BY claim_no;
SELECT coalesce(array_agg(claim_no ORDER BY claim_no)
                = ARRAY['SEC-101-001', 'SEC-101-002'], false) AS tenant_read_ok
FROM :"lab_schema".claim \gset
\if :tenant_read_ok
\echo 'PASS: tenant 101 sees its two claims. SEC-202-001 is invisible.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: tenant 101 should see exactly SEC-101-001 and SEC-101-002.'; END $$;
\endif
INSERT INTO :"lab_schema".claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP7-OK', 'NEW', 500)
RETURNING claim_no, tenant_id;
\echo 'PASS: WITH CHECK allows a row for the current tenant. It will roll back.'
SAVEPOINT gate;
\set ON_ERROR_STOP off
INSERT INTO :"lab_schema".claim (tenant_id, claim_no, status, estimated_amount)
VALUES (202, 'SEC-STEP7-NO', 'NEW', 500);
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: WITH CHECK refuses tenant 202 while the setting is 101 (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected cross-tenant INSERT denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"app_role";
SELECT set_config('app.tenant_id', '', true);
SELECT count(*) AS visible_rows FROM :"lab_schema".claim;
SELECT coalesce(count(*) = 0, false) AS empty_context_ok
FROM :"lab_schema".claim \gset
\if :empty_context_ok
\echo 'PASS: an empty tenant setting shows zero rows.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: an empty tenant setting must show zero rows.'; END $$;
\endif
ROLLBACK;
SELECT row_security_active(format('%I.claim', :'lab_schema')::regclass) AS superuser_policy_applies \gset
\echo 'As postgres, row_security_active is' :superuser_policy_applies
\echo 'false here means this administrator bypasses the policy. App tests above are the proof.'


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 8 — MAINTENANCE'
\echo 'Question: may the DBA collect statistics on claim, and only on claim?'
\echo 'Mechanism: GRANT MAINTAIN ON TABLE. This is not pg_maintain.'
\echo 'MAINTAIN allows ANALYZE and VACUUM. It does not allow INSERT or SELECT.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 8 (Ctrl+C to stop): ' gate_continue
\endif
BEGIN;
SET LOCAL ROLE :"owner_role";
GRANT USAGE ON SCHEMA :"lab_schema" TO :"dba_role";
REVOKE MAINTAIN ON :"lab_schema".claim FROM :"dba_role";
REVOKE MAINTAIN ON :"lab_schema".policyholder FROM :"dba_role";
COMMIT;
SELECT has_table_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'MAINTAIN') AS app_maintain,
       has_table_privilege(:'dba_role', format('%I.claim', :'lab_schema'), 'MAINTAIN') AS dba_maintain,
       pg_has_role(:'dba_role', 'pg_maintain', 'MEMBER') AS dba_has_pg_maintain
\gset
\echo 'App MAINTAIN:' :app_maintain '| DBA MAINTAIN:' :dba_maintain '| member of pg_maintain:' :dba_has_pg_maintain
BEGIN;
SET LOCAL ROLE :"app_role";
SELECT set_config('app.tenant_id', '101', true);
SAVEPOINT gate;
\set ON_ERROR_STOP off
ANALYZE :"lab_schema".claim;
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: the app cannot ANALYZE the claim table (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected app ANALYZE denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"dba_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
ANALYZE :"lab_schema".claim;
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: before GRANT MAINTAIN, the DBA cannot ANALYZE claim (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected DBA ANALYZE denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"owner_role";
GRANT MAINTAIN ON TABLE :"lab_schema".claim TO :"dba_role";
COMMIT;
BEGIN;
SET LOCAL ROLE :"dba_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
ANALYZE :"lab_schema".policyholder;
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: MAINTAIN on claim does not cover policyholder (42501).'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected policyholder ANALYZE denial 42501.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"dba_role";
ANALYZE :"lab_schema".claim;
COMMIT;
\echo 'PASS: the DBA analyzed claim. ANALYZE reads every tenant. The row policy does not sample one tenant.'
BEGIN;
SET LOCAL ROLE :"owner_role";
ANALYZE :"lab_schema".policyholder;
COMMIT;
\echo 'PASS: the owner analyzed policyholder so Step 9 can show column statistics.'
BEGIN;
SET LOCAL ROLE :"dba_role";
SAVEPOINT gate;
\set ON_ERROR_STOP off
INSERT INTO :"lab_schema".claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP8-NO', 'NEW', 500);
\set gate_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT gate;
SELECT :'gate_state' = '42501' AS denied \gset
\if :denied
\echo 'PASS: the DBA cannot INSERT (42501). Maintenance is not data access.'
\else
\echo 'Unexpected SQLSTATE:' :gate_state
DO $$ BEGIN RAISE EXCEPTION 'FAIL: expected DBA INSERT denial 42501.'; END $$;
\endif
ROLLBACK;
SELECT has_table_privilege(:'dba_role', format('%I.claim', :'lab_schema'), 'SELECT') AS dba_can_select,
       has_table_privilege(:'dba_role', format('%I.claim', :'lab_schema'), 'MAINTAIN') AS dba_can_maintain
\gset
\echo 'DBA SELECT:' :dba_can_select '| DBA MAINTAIN:' :dba_can_maintain


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 9 — STATISTICS'
\echo 'Two different pictures of the same table:'
\echo '  pg_stat_user_tables  activity counters for the whole table'
\echo '  pg_stats             planner values, per column'
\echo 'pg_stats shows a column only when the current role may SELECT it,'
\echo 'and hides the table when row security is active for that role.'
\echo 'This session is superuser, so postgres still sees every claim value.'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 9 (Ctrl+C to stop): ' gate_continue
\endif
SELECT relname, n_live_tup, n_tup_ins, seq_scan, analyze_count, last_analyze
FROM pg_stat_user_tables
WHERE schemaname = :'lab_schema'
  AND relname IN ('claim', 'policyholder')
ORDER BY relname;
SELECT coalesce(bool_or(relname = 'claim' AND last_analyze IS NOT NULL), false) AS claim_analyzed
FROM pg_stat_user_tables
WHERE schemaname = :'lab_schema' \gset
\if :claim_analyzed
\echo 'PASS: claim has been analyzed. n_live_tup counts every tenant, including 202.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: claim.last_analyze is empty. Step 8 did not leave statistics.'; END $$;
\endif
\echo 'Planner statistics visible to postgres (row security is bypassed):'
SELECT attname, n_distinct, most_common_vals
FROM pg_stats
WHERE schemaname = :'lab_schema'
  AND tablename = 'claim'
  AND NOT inherited
ORDER BY attname;
-- Three seed rows are too few for ANALYZE to list every tenant as a common
-- value. tenant_id still has a statistics row. The app, under row security,
-- is shown none of those rows.
SELECT coalesce(bool_or(attname = 'tenant_id'), false) AS admin_sees_tenant_stats
FROM pg_stats
WHERE schemaname = :'lab_schema'
  AND tablename = 'claim'
  AND NOT inherited \gset
\if :admin_sees_tenant_stats
\echo 'PASS: postgres can read claim.tenant_id statistics. The list above includes tenant 101.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: postgres should see a pg_stats row for claim.tenant_id.'; END $$;
\endif
BEGIN;
SET LOCAL ROLE :"app_role";
SELECT set_config('app.tenant_id', '101', true);
SELECT count(*) AS rows_app_can_read,
       (SELECT n_live_tup
        FROM pg_stat_user_tables
        WHERE schemaname = :'lab_schema' AND relname = 'claim') AS rows_in_activity_stats
FROM :"lab_schema".claim;
SELECT count(*) AS claim_value_stats_visible
FROM pg_stats
WHERE schemaname = :'lab_schema' AND tablename = 'claim';
SELECT coalesce(count(*) = 0, false) AS rls_hides_value_stats
FROM pg_stats
WHERE schemaname = :'lab_schema' AND tablename = 'claim' \gset
\if :rls_hides_value_stats
\echo 'PASS: the app has SELECT, and active row security hides pg_stats for claim.'
\echo 'The activity counter above can still describe the whole table.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: the app should see no pg_stats rows for claim while row security applies.'; END $$;
\endif
ROLLBACK;
BEGIN;
SET LOCAL ROLE :"auditor_role";
SELECT attname, n_distinct, most_common_vals
FROM pg_stats
WHERE schemaname = :'lab_schema'
  AND tablename = 'policyholder'
  AND NOT inherited
ORDER BY attname;
SELECT coalesce(bool_or(attname = 'full_name'), false)
       AND NOT coalesce(bool_or(attname = 'email'), false)
       AND NOT coalesce(bool_or(attname = 'phone'), false) AS column_stats_match_grant
FROM pg_stats
WHERE schemaname = :'lab_schema'
  AND tablename = 'policyholder'
  AND NOT inherited \gset
\if :column_stats_match_grant
\echo 'PASS: the auditor sees statistics for full_name and not for email or phone.'
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL: policyholder pg_stats should follow the auditor column grant.'; END $$;
\endif
ROLLBACK;
SELECT pg_has_role(:'app_role', 'pg_read_all_stats', 'MEMBER') AS app_reads_all_stats,
       pg_has_role(:'app_role', 'pg_monitor', 'MEMBER') AS app_is_monitor,
       pg_has_role(:'dba_role', 'pg_read_all_stats', 'MEMBER') AS dba_reads_all_stats,
       pg_has_role(:'dba_role', 'pg_maintain', 'MEMBER') AS dba_maintains_every_table
\gset
\echo 'App member of pg_read_all_stats:' :app_reads_all_stats '| pg_monitor:' :app_is_monitor
\echo 'DBA member of pg_read_all_stats:' :dba_reads_all_stats '| pg_maintain:' :dba_maintains_every_table
\if :app_reads_all_stats
DO $$ BEGIN RAISE EXCEPTION 'FAIL: this walkthrough must not grant pg_read_all_stats.'; END $$;
\else
\echo 'PASS: statistics in this lab are about these tables. Other sessions stay closed.'
\endif
\echo 'Own backend only. Other sessions are a pg_read_all_stats question, and it stays closed.'
SELECT pid, usename, datname, state
FROM pg_stat_activity
WHERE pid = pg_backend_pid();
\echo 'Reference only. The script does not grant these cluster-wide roles:'
SELECT rolname
FROM pg_roles
WHERE rolname IN ('pg_monitor', 'pg_read_all_stats', 'pg_read_all_settings',
                   'pg_stat_scan_tables', 'pg_maintain')
ORDER BY rolname;


\echo ''
\echo '----------------------------------------------------------------'
\echo 'STEP 10 — THE PATH, AFTER EVERY GATE'
\echo '----------------------------------------------------------------'
\if :guided_mode
\prompt 'Press Enter to run Step 10 (Ctrl+C to stop): ' gate_continue
\endif
SELECT step, check_name, allowed
FROM (VALUES
    (2, 'app CONNECT',
        has_database_privilege(:'app_role', :'lab_database', 'CONNECT')),
    (3, 'app schema USAGE',
        has_schema_privilege(:'app_role', :'lab_schema', 'USAGE')),
    (3, 'app schema CREATE',
        has_schema_privilege(:'app_role', :'lab_schema', 'CREATE')),
    (4, 'app SELECT claim',
        has_table_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'SELECT')),
    (5, 'app INSERT claim',
        has_table_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'INSERT')),
    (5, 'app DELETE claim',
        has_table_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'DELETE')),
    (5, 'app TRUNCATE claim',
        has_table_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'TRUNCATE')),
    (6, 'app UPDATE status',
        has_column_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'status', 'UPDATE')),
    (6, 'app UPDATE amount',
        has_column_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'estimated_amount', 'UPDATE')),
    (6, 'auditor SELECT email',
        has_column_privilege(:'auditor_role', format('%I.policyholder', :'lab_schema'), 'email', 'SELECT')),
    (8, 'app MAINTAIN claim',
        has_table_privilege(:'app_role', format('%I.claim', :'lab_schema'), 'MAINTAIN')),
    (8, 'DBA MAINTAIN claim',
        has_table_privilege(:'dba_role', format('%I.claim', :'lab_schema'), 'MAINTAIN')),
    (8, 'DBA SELECT claim',
        has_table_privilege(:'dba_role', format('%I.claim', :'lab_schema'), 'SELECT')),
    (1, 'app is a member of the owner',
        pg_has_role(:'app_role', :'owner_role', 'MEMBER'))
) AS gate(step, check_name, allowed)
ORDER BY step, check_name;
\echo 'Expected closed checks: schema CREATE, DELETE, TRUNCATE, amount UPDATE,'
\echo 'auditor email, app MAINTAIN, DBA SELECT, and owner membership.'
SELECT c.relname, pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'lab_schema' AND c.relkind = 'r'
ORDER BY c.relname;
SELECT tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE schemaname = :'lab_schema'
ORDER BY tablename, policyname;
\echo 'COMPLETE: user -> connection -> schema -> table -> operation -> column -> row -> maintenance -> statistics.'
\echo 'Seed claims remain. Sample writes were rolled back. Row security stays enabled on claim.'
\echo 'For a real login test, as postgres run \password' :app_role
\echo 'Then: psql -h HOST -p PORT -U' :app_role '-d' :lab_database
\echo 'Remove this walkthrough with scripts/sql/04-security-gates-walkthrough-reset.sql'

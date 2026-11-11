\set ON_ERROR_STOP on
-- Replace every xx with your assigned two-digit number before running.
DO $$
BEGIN
  IF current_database() <> 'claimsure_xx' OR session_user <> 'student_xx' THEN
    RAISE EXCEPTION 'Wrong connection or unresolved xx placeholder; verify your assigned database/login first';
  END IF;
END $$;

-- Security gates, plain SQL, student xx.
-- Run one step at a time in this order. Do not execute the whole file at once.
-- PostgreSQL 18.
--
-- Before this file, postgres runs 04-security-gates-activate-student.sql once.
-- That activation creates the five gate roles and lets this login SET ROLE
-- to them. It does not grant CREATEROLE, and it does not create the schema.
--
-- Login for every step in this file: student_xx, database claimsure_xx.
-- The prompt must be claimsure_xx=>
-- A prompt of claimsure_xx=# is postgres. Use postgres only for the
-- activation file and for 04-security-gates-reset-student.sql.
--
-- Stay in this one student_xx session. Do not open a new login for each role.
-- SET ROLE changes only current_user. session_user stays student_xx.
-- RESET ROLE returns current_user to student_xx. It does not change the login.
-- Privileges of gate_owner_xx are not inherited until SET ROLE.
--
--   Step 0    student_xx checks the session.
--   Step 1    student_xx sees the roles postgres created, fails to create
--             another role, then grants gate_staff_xx to gate_app_xx.
--   Step 2    student_xx grants CONNECT, then briefly becomes gate_app_xx.
--   Step 3    student_xx creates the schema.
--             gate_owner_xx grants USAGE. gate_app_xx is the expected error.
--   Step 4    gate_owner_xx creates claim and grants SELECT. gate_app_xx reads.
--   Step 5    gate_owner_xx grants each operation. gate_app_xx tries each one.
--   Step 6    gate_owner_xx grants columns.
--             gate_auditor_xx and gate_app_xx try them.
--   Step 7    gate_owner_xx creates the row policy. gate_app_xx reads and writes.
--   Step 8    gate_owner_xx grants MAINTAIN. gate_dba_xx runs ANALYZE.
--   Step 9    student_xx reads statistics.
--             gate_app_xx and gate_auditor_xx read inside a transaction.
--   Step 10   student_xx reads the final checks.
--
--   gate_owner_xx     cannot log in. Owns schema lab_gate_xx.
--   gate_staff_xx     cannot log in. Holds the application privileges.
--   gate_app_xx       logs in and inherits gate_staff_xx.
--   gate_auditor_xx   logs in. Reads names, not email or phone.
--   gate_dba_xx       logs in. ANALYZE on claim only.
--
-- A line marked EXPECTED ERROR is supposed to fail.
-- Read the error, then run the next step.
-- If the session says the transaction is aborted, run:
--   ROLLBACK;
-- Then continue at the next step.
--
-- This file does not change schema insurance or schema public.
-- To remove it afterwards, run 04-security-gates-reset-student.sql.

-- =============================================================================
-- Step 0 — Session
-- Login: student_xx. Acts as: student_xx.
-- Question: am I student xx, in claimsure_xx, on PostgreSQL 18, allowed to
-- act as the gate roles without being superuser?
-- Continue only when every boolean column is true.
-- If can_set_owner is false, postgres has not run the activation file.
-- =============================================================================

-- rolsuper is a column of pg_roles, not a session function.
SELECT current_database() AS database_name,
       session_user AS login_user,
       current_user AS effective_user,
       current_database() = 'claimsure_xx' AS correct_database,
       session_user = 'student_xx' AND current_user = session_user AS correct_login,
       NOT rolsuper AS not_superuser,
       current_setting('server_version_num')::int >= 180000 AS postgresql_18,
       has_database_privilege(session_user, current_database(), 'CREATE') AS can_create_schema,
       has_database_privilege(
           session_user, current_database(), 'CONNECT WITH GRANT OPTION'
       ) AS can_grant_connect,
       EXISTS (
           SELECT 1
           FROM pg_auth_members am
           JOIN pg_roles granted ON granted.oid = am.roleid
           JOIN pg_roles member ON member.oid = am.member
           WHERE member.rolname = session_user
             AND granted.rolname = 'gate_owner_xx'
             AND am.set_option
             AND NOT am.inherit_option
       ) AS can_set_owner,
       EXISTS (
           SELECT 1
           FROM pg_auth_members am
           JOIN pg_roles granted ON granted.oid = am.roleid
           JOIN pg_roles member ON member.oid = am.member
           WHERE member.rolname = session_user
             AND granted.rolname = 'gate_app_xx'
             AND am.set_option
             AND NOT am.inherit_option
       ) AS can_set_app,
       EXISTS (
           SELECT 1
           FROM pg_auth_members am
           JOIN pg_roles granted ON granted.oid = am.roleid
           JOIN pg_roles member ON member.oid = am.member
           WHERE member.rolname = session_user
             AND granted.rolname = 'gate_auditor_xx'
             AND am.set_option
             AND NOT am.inherit_option
       ) AS can_set_auditor,
       EXISTS (
           SELECT 1
           FROM pg_auth_members am
           JOIN pg_roles granted ON granted.oid = am.roleid
           JOIN pg_roles member ON member.oid = am.member
           WHERE member.rolname = session_user
             AND granted.rolname = 'gate_dba_xx'
             AND am.set_option
             AND NOT am.inherit_option
       ) AS can_set_dba,
       EXISTS (
           SELECT 1
           FROM pg_auth_members am
           JOIN pg_roles granted ON granted.oid = am.roleid
           JOIN pg_roles member ON member.oid = am.member
           WHERE member.rolname = session_user
             AND granted.rolname = 'gate_staff_xx'
             AND am.set_option
             AND am.admin_option
             AND NOT am.inherit_option
       ) AS can_administer_staff
FROM pg_roles
WHERE rolname = current_user;


-- =============================================================================
-- Step 1 — User
-- Login: student_xx. Acts as: student_xx.
-- Question: who are the identities, before any object privilege exists?
-- postgres created these roles. A role name is not a privilege.
-- None of these roles is superuser.
-- =============================================================================

-- Expect five roles. Only gate_app_xx, gate_auditor_xx, and gate_dba_xx can log in.
-- rolsuper, rolcreaterole, and rolbypassrls are false for every row.
SELECT rolname, rolcanlogin, rolinherit, rolsuper, rolcreaterole, rolbypassrls
FROM pg_roles
WHERE rolname IN (
    'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
    'gate_auditor_xx', 'gate_dba_xx'
)
ORDER BY rolname;

-- Step 1.1 — EXPECTED ERROR. Run this one statement alone.
-- Result: permission denied to create role.
-- Creating a role is the part that stays with postgres.
CREATE ROLE gate_not_allowed_xx NOLOGIN;

-- Membership does not copy privileges the group does not have yet.
-- This GRANT works because the activation gave student_xx ADMIN on
-- gate_staff_xx only.
GRANT gate_staff_xx TO gate_app_xx
    WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;

-- Expect one row: gate_app_xx is a member of gate_staff_xx, without ADMIN.
SELECT r.rolname AS group_role,
       m.rolname AS member,
       am.inherit_option,
       am.set_option,
       am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname = 'gate_app_xx';


-- =============================================================================
-- Step 2 — Connection
-- Login: student_xx. GRANT CONNECT runs as student_xx.
-- The last check uses SET ROLE gate_app_xx, then RESET ROLE.
-- Question: may gate_app_xx start a session in claimsure_xx?
-- Mechanism: GRANT CONNECT.
-- Still closed after this step: schema USAGE.
-- This script does not change PUBLIC. public_connect shows the current grant.
-- =============================================================================

SELECT has_database_privilege('gate_app_xx', 'claimsure_xx', 'CONNECT') AS app_connect_before,
       has_database_privilege('public', 'claimsure_xx', 'CONNECT') AS public_connect;

GRANT CONNECT ON DATABASE claimsure_xx
    TO gate_app_xx, gate_auditor_xx, gate_dba_xx;

-- Expect app_connect_after = true.
SELECT has_database_privilege('gate_app_xx', 'claimsure_xx', 'CONNECT') AS app_connect_after;

-- login_user stays student_xx. effective_role becomes gate_app_xx.
-- This switches the privilege check. It does not test the password.
SET ROLE gate_app_xx;
SELECT session_user AS login_user, current_user AS effective_role;
RESET ROLE;


-- =============================================================================
-- Step 3 — Schema
-- Login: student_xx.
-- CREATE SCHEMA runs as student_xx. The schema owner is gate_owner_xx.
-- REVOKE and GRANT USAGE run as gate_owner_xx.
-- The expected errors run as gate_app_xx. RESET ROLE returns to student_xx.
-- Question: may the app resolve objects in lab_gate_xx?
-- The owner grants USAGE. USAGE does not include CREATE.
-- =============================================================================

CREATE SCHEMA lab_gate_xx AUTHORIZATION gate_owner_xx;

SET ROLE gate_owner_xx;
REVOKE ALL ON SCHEMA lab_gate_xx FROM PUBLIC;
RESET ROLE;

-- Step 3.1 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for schema lab_gate_xx
SET ROLE gate_app_xx;
SELECT count(*) FROM lab_gate_xx.claim;

-- Step 3.2 — Run this after the error. Login is still student_xx.
RESET ROLE;

-- These three lines act as gate_owner_xx, then return to student_xx.
SET ROLE gate_owner_xx;
GRANT USAGE ON SCHEMA lab_gate_xx TO gate_staff_xx;
RESET ROLE;

-- Expect app_can_resolve = true and app_can_create = false.
-- The app inherits USAGE from gate_staff_xx.
SELECT has_schema_privilege('gate_app_xx', 'lab_gate_xx', 'USAGE') AS app_can_resolve,
       has_schema_privilege('gate_app_xx', 'lab_gate_xx', 'CREATE') AS app_can_create;

-- Step 3.3 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for schema lab_gate_xx
SET ROLE gate_app_xx;
CREATE TABLE lab_gate_xx.not_allowed (id integer);

-- Step 3.4 — Run this after the error.
RESET ROLE;


-- =============================================================================
-- Step 4 — Table
-- Login: student_xx. Create, seed, and GRANT SELECT run as gate_owner_xx.
-- The expected error and the successful read run as gate_app_xx.
-- Question: may the app read claims?
-- Mechanism: GRANT SELECT on the table.
-- Still closed after this step: INSERT.
-- Seed: tenant 101 has two claims. Tenant 202 has one claim.
-- =============================================================================

SET ROLE gate_owner_xx;

CREATE TABLE lab_gate_xx.claim (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    claim_no text NOT NULL UNIQUE,
    status text NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO lab_gate_xx.claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-101-001', 'NEW', 10000),
       (101, 'SEC-101-002', 'UNDER_REVIEW', 25000),
       (202, 'SEC-202-001', 'NEW', 18000);

REVOKE ALL ON lab_gate_xx.claim FROM PUBLIC;
RESET ROLE;

-- The identity sequence. The later nextval() test uses this name.
SELECT pg_get_serial_sequence('lab_gate_xx.claim', 'claim_id') AS claim_id_seq;

-- Step 4.1 — EXPECTED ERROR. Run these two statements.
-- Schema USAGE is already open. Result: permission denied for table claim
SET ROLE gate_app_xx;
SELECT claim_no FROM lab_gate_xx.claim;

-- Step 4.2 — Run this after the error.
RESET ROLE;

SET ROLE gate_owner_xx;
GRANT SELECT ON lab_gate_xx.claim TO gate_staff_xx;
RESET ROLE;

-- Expect three rows: SEC-101-001, SEC-101-002, and SEC-202-001.
-- Row security is not on yet, so tenant 202 is visible.
SET ROLE gate_app_xx;
SELECT claim_no, tenant_id, status, estimated_amount
FROM lab_gate_xx.claim
ORDER BY claim_no;
RESET ROLE;

-- Expect app_can_insert = false. SELECT did not open INSERT.
SELECT has_table_privilege('gate_app_xx', 'lab_gate_xx.claim', 'INSERT') AS app_can_insert;


-- =============================================================================
-- Step 5 — Operation
-- Login: student_xx. Each GRANT runs as gate_owner_xx.
-- Each denial and each successful command runs as gate_app_xx.
-- Question: which commands may the app run?
-- INSERT, direct nextval(), UPDATE, DELETE, and TRUNCATE are separate.
-- An identity INSERT does not need USAGE on the sequence.
-- A direct nextval() call does.
-- =============================================================================

-- Step 5.1 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for table claim
SET ROLE gate_app_xx;
INSERT INTO lab_gate_xx.claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP5-TEMP', 'NEW', 500);

-- Step 5.2 — Run this after the error.
RESET ROLE;

SET ROLE gate_owner_xx;
GRANT INSERT ON lab_gate_xx.claim TO gate_staff_xx;
RESET ROLE;

-- Run this transaction as a whole. RETURNING shows the new row.
-- ROLLBACK removes it. The three seed claims remain.
BEGIN;
SET LOCAL ROLE gate_app_xx;
INSERT INTO lab_gate_xx.claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP5-TEMP', 'NEW', 500)
RETURNING claim_no, tenant_id, status;
ROLLBACK;

-- Step 5.3 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for sequence claim_claim_id_seq
SET ROLE gate_app_xx;
SELECT nextval('lab_gate_xx.claim_claim_id_seq');

-- Step 5.4 — Run this after the error.
RESET ROLE;

SET ROLE gate_owner_xx;
GRANT USAGE ON SEQUENCE lab_gate_xx.claim_claim_id_seq TO gate_staff_xx;
RESET ROLE;

-- Expect one number. nextval() moves forward even if you roll back later work.
SET ROLE gate_app_xx;
SELECT nextval('lab_gate_xx.claim_claim_id_seq') AS sequence_value_after_usage_grant;
RESET ROLE;

-- Step 5.5 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for table claim
SET ROLE gate_app_xx;
DELETE FROM lab_gate_xx.claim WHERE claim_no = 'SEC-101-001';

-- Step 5.6 — Run this after the error.
RESET ROLE;

-- Step 5.7 — EXPECTED ERROR. Run these two statements.
-- TRUNCATE is not DELETE. Result: permission denied for table claim
SET ROLE gate_app_xx;
TRUNCATE lab_gate_xx.claim;

-- Step 5.8 — Run this after the error.
RESET ROLE;

SET ROLE gate_owner_xx;
GRANT UPDATE ON lab_gate_xx.claim TO gate_staff_xx;
RESET ROLE;

-- Run this transaction as a whole. The amount changes, then ROLLBACK restores it.
-- Step 6 takes this table-wide UPDATE away.
BEGIN;
SET LOCAL ROLE gate_app_xx;
UPDATE lab_gate_xx.claim
SET estimated_amount = estimated_amount + 1,
    updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, estimated_amount;
ROLLBACK;


-- =============================================================================
-- Step 6 — Column
-- Login: student_xx. The table and the column grants run as gate_owner_xx.
-- Name reads and the email denial run as gate_auditor_xx.
-- The status update and the amount denial run as gate_app_xx.
-- Question: which columns may each identity use?
-- The auditor reads policyholder names. Email and phone stay closed.
-- The app may change status and updated_at. The amount closes.
-- =============================================================================

SET ROLE gate_owner_xx;

CREATE TABLE lab_gate_xx.policyholder (
    policyholder_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    UNIQUE (tenant_id, email)
);

INSERT INTO lab_gate_xx.policyholder (tenant_id, full_name, email, phone)
VALUES (101, 'Demo Policyholder', 'demo@example.invalid', '000-000-0000');

REVOKE ALL ON lab_gate_xx.policyholder FROM PUBLIC;
GRANT USAGE ON SCHEMA lab_gate_xx TO gate_auditor_xx;
GRANT SELECT (policyholder_id, tenant_id, full_name)
    ON lab_gate_xx.policyholder TO gate_auditor_xx;

REVOKE UPDATE ON lab_gate_xx.claim FROM gate_staff_xx;
GRANT UPDATE (status, updated_at) ON lab_gate_xx.claim TO gate_staff_xx;
RESET ROLE;

-- Expect auditor_name = true, auditor_email = false,
-- app_status = true, app_amount = false.
SELECT has_column_privilege(
           'gate_auditor_xx', 'lab_gate_xx.policyholder', 'full_name', 'SELECT'
       ) AS auditor_name,
       has_column_privilege(
           'gate_auditor_xx', 'lab_gate_xx.policyholder', 'email', 'SELECT'
       ) AS auditor_email,
       has_column_privilege(
           'gate_app_xx', 'lab_gate_xx.claim', 'status', 'UPDATE'
       ) AS app_status,
       has_column_privilege(
           'gate_app_xx', 'lab_gate_xx.claim', 'estimated_amount', 'UPDATE'
       ) AS app_amount;

-- Expect one row: Demo Policyholder. Email is not in this query.
SET ROLE gate_auditor_xx;
SELECT policyholder_id, tenant_id, full_name
FROM lab_gate_xx.policyholder
ORDER BY policyholder_id;
RESET ROLE;

-- Step 6.1 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for table policyholder
SET ROLE gate_auditor_xx;
SELECT email, phone FROM lab_gate_xx.policyholder;

-- Step 6.2 — Run this after the error.
RESET ROLE;

-- Run this transaction as a whole. Status becomes APPROVED, then ROLLBACK.
BEGIN;
SET LOCAL ROLE gate_app_xx;
UPDATE lab_gate_xx.claim
SET status = 'APPROVED',
    updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, status;
ROLLBACK;

-- Step 6.3 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for table claim
SET ROLE gate_app_xx;
UPDATE lab_gate_xx.claim
SET estimated_amount = 1
WHERE claim_no = 'SEC-101-001';

-- Step 6.4 — Run this after the error.
RESET ROLE;


-- =============================================================================
-- Step 7 — Row
-- Login: student_xx. The policy is created as gate_owner_xx.
-- Reads and writes run as gate_app_xx inside a transaction.
-- Question: which rows may the app see or write?
-- The policy compares tenant_id with the setting app.tenant_id.
-- FORCE ROW LEVEL SECURITY applies the policy to the table owner too.
-- student_xx does not bypass it. A superuser session would.
-- The application must set the tenant only after it has authorized that tenant.
-- =============================================================================

SET ROLE gate_owner_xx;
ALTER TABLE lab_gate_xx.claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_gate_xx.claim FORCE ROW LEVEL SECURITY;
CREATE POLICY claim_tenant ON lab_gate_xx.claim
    FOR ALL
    TO gate_staff_xx
    USING (tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint)
    WITH CHECK (tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint);
RESET ROLE;

-- Run this transaction as a whole.
-- Expect row_policy_applies = true.
-- Expect two claims: SEC-101-001 and SEC-101-002.
-- The insert for tenant 101 succeeds, then ROLLBACK removes it.
BEGIN;
SET LOCAL ROLE gate_app_xx;
SELECT set_config('app.tenant_id', '101', true);
SELECT current_user AS effective_role,
       row_security_active('lab_gate_xx.claim'::regclass) AS row_policy_applies;
SELECT claim_no, tenant_id
FROM lab_gate_xx.claim
ORDER BY claim_no;
INSERT INTO lab_gate_xx.claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP7-OK', 'NEW', 500)
RETURNING claim_no, tenant_id;
ROLLBACK;

-- Step 7.1 — EXPECTED ERROR. Run this transaction until the INSERT fails.
-- Result: new row violates row-level security policy for table claim
-- Then run ROLLBACK; before Step 7.2.
BEGIN;
SET LOCAL ROLE gate_app_xx;
SELECT set_config('app.tenant_id', '101', true);
INSERT INTO lab_gate_xx.claim (tenant_id, claim_no, status, estimated_amount)
VALUES (202, 'SEC-STEP7-NO', 'NEW', 500);

-- Step 7.2 — Run this after the error above.
ROLLBACK;

-- Run this transaction as a whole.
-- Expect visible_rows = 0. An empty tenant setting matches no row.
BEGIN;
SET LOCAL ROLE gate_app_xx;
SELECT set_config('app.tenant_id', '', true);
SELECT count(*) AS visible_rows
FROM lab_gate_xx.claim;
ROLLBACK;

-- Expect true. This login is not a superuser, so the policy applies here too.
-- The app transaction above is the proof of which rows are visible.
SELECT current_user AS login_user,
       row_security_active('lab_gate_xx.claim'::regclass) AS row_policy_applies_to_student;


-- =============================================================================
-- Step 8 — Maintenance
-- Login: student_xx. GRANT MAINTAIN runs as gate_owner_xx.
-- ANALYZE on claim runs as gate_dba_xx. The app denial runs as gate_app_xx.
-- Question: may the DBA collect statistics on claim, and only on claim?
-- Mechanism: GRANT MAINTAIN on that table.
-- MAINTAIN allows ANALYZE. It does not allow INSERT or SELECT.
-- This is not membership in pg_maintain.
-- =============================================================================

SET ROLE gate_owner_xx;
GRANT USAGE ON SCHEMA lab_gate_xx TO gate_dba_xx;
RESET ROLE;

-- Expect app_maintain = false, dba_maintain = false, dba_has_pg_maintain = false.
SELECT has_table_privilege('gate_app_xx', 'lab_gate_xx.claim', 'MAINTAIN') AS app_maintain,
       has_table_privilege('gate_dba_xx', 'lab_gate_xx.claim', 'MAINTAIN') AS dba_maintain,
       pg_has_role('gate_dba_xx', 'pg_maintain', 'MEMBER') AS dba_has_pg_maintain;

-- Step 8.1 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for table claim
SET ROLE gate_app_xx;
ANALYZE lab_gate_xx.claim;

-- Step 8.2 — Run this after the error.
RESET ROLE;

-- Step 8.3 — EXPECTED ERROR. Run these two statements.
-- The DBA can see the schema name, and still cannot analyze yet.
SET ROLE gate_dba_xx;
ANALYZE lab_gate_xx.claim;

-- Step 8.4 — Run this after the error.
RESET ROLE;

SET ROLE gate_owner_xx;
GRANT MAINTAIN ON TABLE lab_gate_xx.claim TO gate_dba_xx;
RESET ROLE;

-- Step 8.5 — EXPECTED ERROR. Run these two statements.
-- MAINTAIN on claim does not cover policyholder.
SET ROLE gate_dba_xx;
ANALYZE lab_gate_xx.policyholder;

-- Step 8.6 — Run this after the error.
RESET ROLE;

-- This ANALYZE succeeds. It reads every tenant. The row policy does not
-- reduce the sample to tenant 101.
SET ROLE gate_dba_xx;
ANALYZE lab_gate_xx.claim;
RESET ROLE;

-- The owner analyzes policyholder so Step 9 can show column statistics.
-- The DBA was not given MAINTAIN on this table.
SET ROLE gate_owner_xx;
ANALYZE lab_gate_xx.policyholder;
RESET ROLE;

-- Step 8.7 — EXPECTED ERROR. Run these two statements.
-- Result: permission denied for table claim
SET ROLE gate_dba_xx;
INSERT INTO lab_gate_xx.claim (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-STEP8-NO', 'NEW', 500);

-- Step 8.8 — Run this after the error.
RESET ROLE;

-- Expect dba_can_select = false and dba_can_maintain = true.
SELECT has_table_privilege('gate_dba_xx', 'lab_gate_xx.claim', 'SELECT') AS dba_can_select,
       has_table_privilege('gate_dba_xx', 'lab_gate_xx.claim', 'MAINTAIN') AS dba_can_maintain;


-- =============================================================================
-- Step 9 — Statistics
-- Login: student_xx. The first queries run as student_xx.
-- The app and auditor reads use SET LOCAL ROLE inside a transaction.
-- pg_stat_user_tables counts activity for the whole table.
-- pg_stats shows planner values for one column.
-- pg_stats shows a column only when the current role may SELECT it.
-- pg_stats hides the table when row security is active for that role.
-- A superuser would still see claim values. This login does not switch back.
-- =============================================================================

-- Expect claim.analyzed = true. n_live_tup counts tenant 202 as well as 101.
SELECT relname, n_live_tup, n_tup_ins, seq_scan, analyze_count, last_analyze
FROM pg_stat_user_tables
WHERE schemaname = 'lab_gate_xx'
  AND relname IN ('claim', 'policyholder')
ORDER BY relname;

-- Expect no rows. student_xx cannot SELECT claim, and row security is active.
-- With only three rows, a superuser would see tenant 101 in most_common_vals.
-- 202 may be absent from that list. This login does not show those values.
SELECT attname, n_distinct, most_common_vals
FROM pg_stats
WHERE schemaname = 'lab_gate_xx'
  AND tablename = 'claim'
  AND NOT inherited
ORDER BY attname;

-- Run this transaction as a whole.
-- Expect rows_app_can_read = 2.
-- Expect rows_in_activity_stats = 3, the whole table.
-- Expect claim_value_stats_visible = 0. Active row security hides pg_stats.
BEGIN;
SET LOCAL ROLE gate_app_xx;
SELECT set_config('app.tenant_id', '101', true);
SELECT count(*) AS rows_app_can_read,
       (SELECT n_live_tup
        FROM pg_stat_user_tables
        WHERE schemaname = 'lab_gate_xx'
          AND relname = 'claim') AS rows_in_activity_stats
FROM lab_gate_xx.claim;
SELECT count(*) AS claim_value_stats_visible
FROM pg_stats
WHERE schemaname = 'lab_gate_xx'
  AND tablename = 'claim';
ROLLBACK;

-- Run this transaction as a whole.
-- Expect full_name, policyholder_id, and tenant_id.
-- Expect no row for email and no row for phone.
BEGIN;
SET LOCAL ROLE gate_auditor_xx;
SELECT attname, n_distinct, most_common_vals
FROM pg_stats
WHERE schemaname = 'lab_gate_xx'
  AND tablename = 'policyholder'
  AND NOT inherited
ORDER BY attname;
ROLLBACK;

-- Expect every column false. Other sessions stay closed.
SELECT pg_has_role('gate_app_xx', 'pg_read_all_stats', 'MEMBER') AS app_reads_all_stats,
       pg_has_role('gate_app_xx', 'pg_monitor', 'MEMBER') AS app_is_monitor,
       pg_has_role('gate_dba_xx', 'pg_read_all_stats', 'MEMBER') AS dba_reads_all_stats,
       pg_has_role('gate_dba_xx', 'pg_maintain', 'MEMBER') AS dba_maintains_every_table;

-- This backend only.
SELECT pid, usename, datname, state
FROM pg_stat_activity
WHERE pid = pg_backend_pid();

-- These cluster-wide roles exist. This lab does not grant them.
SELECT rolname
FROM pg_roles
WHERE rolname IN (
    'pg_monitor', 'pg_read_all_stats', 'pg_read_all_settings',
    'pg_stat_scan_tables', 'pg_maintain'
)
ORDER BY rolname;


-- =============================================================================
-- Step 10 — Read the whole path
-- Login: student_xx. Acts as: student_xx.
-- Closed checks must be false:
--   schema CREATE, DELETE, TRUNCATE, amount UPDATE,
--   auditor email, app MAINTAIN, DBA SELECT, member of the owner.
-- claim.rls_enabled and claim.force_rls are true.
-- The owner of both tables is gate_owner_xx.
-- =============================================================================

SELECT step, check_name, allowed
FROM (VALUES
    (2, 'app CONNECT',
        has_database_privilege('gate_app_xx', 'claimsure_xx', 'CONNECT')),
    (3, 'app schema USAGE',
        has_schema_privilege('gate_app_xx', 'lab_gate_xx', 'USAGE')),
    (3, 'app schema CREATE',
        has_schema_privilege('gate_app_xx', 'lab_gate_xx', 'CREATE')),
    (4, 'app SELECT claim',
        has_table_privilege('gate_app_xx', 'lab_gate_xx.claim', 'SELECT')),
    (5, 'app INSERT claim',
        has_table_privilege('gate_app_xx', 'lab_gate_xx.claim', 'INSERT')),
    (5, 'app DELETE claim',
        has_table_privilege('gate_app_xx', 'lab_gate_xx.claim', 'DELETE')),
    (5, 'app TRUNCATE claim',
        has_table_privilege('gate_app_xx', 'lab_gate_xx.claim', 'TRUNCATE')),
    (6, 'app UPDATE status',
        has_column_privilege('gate_app_xx', 'lab_gate_xx.claim', 'status', 'UPDATE')),
    (6, 'app UPDATE amount',
        has_column_privilege('gate_app_xx', 'lab_gate_xx.claim', 'estimated_amount', 'UPDATE')),
    (6, 'auditor SELECT email',
        has_column_privilege('gate_auditor_xx', 'lab_gate_xx.policyholder', 'email', 'SELECT')),
    (8, 'app MAINTAIN claim',
        has_table_privilege('gate_app_xx', 'lab_gate_xx.claim', 'MAINTAIN')),
    (8, 'DBA MAINTAIN claim',
        has_table_privilege('gate_dba_xx', 'lab_gate_xx.claim', 'MAINTAIN')),
    (8, 'DBA SELECT claim',
        has_table_privilege('gate_dba_xx', 'lab_gate_xx.claim', 'SELECT')),
    (1, 'app is a member of the owner',
        pg_has_role('gate_app_xx', 'gate_owner_xx', 'MEMBER'))
) AS gate(step, check_name, allowed)
ORDER BY step, check_name;

SELECT c.relname,
       pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab_gate_xx'
  AND c.relkind = 'r'
ORDER BY c.relname;

SELECT tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'lab_gate_xx'
ORDER BY tablename, policyname;

-- End of student xx. Seed claims remain. Row security stays enabled on claim.
-- Remove this lab with 04-security-gates-reset-student.sql.

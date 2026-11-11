\set ON_ERROR_STOP on
-- Replace every xx with your assigned two-digit number before running.
DO $$
BEGIN
  IF current_database() <> 'claimsure_xx' THEN
    RAISE EXCEPTION 'Wrong connection or unresolved xx placeholder; verify your assigned database/login first';
  END IF;
END $$;

-- Activate the security-gates lab for student xx. Plain SQL.
-- Run this file once, as postgres, connected to claimsure_xx.
-- The prompt must be claimsure_xx=#
-- Then reconnect as student_xx and run 04-security-gates-student.sql.
-- The student prompt is claimsure_xx=>
--
-- postgres does only the first activation. student_xx cannot:
--   create roles, because that needs CREATEROLE or superuser
--   comment on a role
--   SET ROLE to a role it has not been granted
-- This file does not grant CREATEROLE to student_xx.
-- CREATEROLE is cluster-wide. The lab roles stay NOSUPERUSER,
-- NOCREATEROLE, and NOBYPASSRLS.
--
-- After this file, student_xx can SET ROLE to each gate role.
-- student_xx does not inherit those privileges while current_user
-- is still student_xx. INHERIT is false on every grant below.
-- ADMIN is true only on gate_staff_xx, so the student can grant
-- that one group to gate_app_xx.
--
-- Skip a CREATE ROLE line when that role already exists.
-- Stop when an existing role has a comment other than
-- "Security gates lab xx".
-- To start over, run 04-security-gates-reset-student.sql as postgres,
-- then run this file again.

-- =============================================================================
-- Step 0 — Session
-- Login: postgres. Acts as: postgres.
-- Continue only when correct_database, administrator, and postgresql_18
-- are true, and student_xx already exists.
-- =============================================================================

-- rolsuper is a column of pg_roles, not a session function.
SELECT current_database() AS database_name,
       session_user AS login_user,
       current_user AS effective_user,
       current_database() = 'claimsure_xx' AS correct_database,
       current_user = session_user AND rolsuper AS administrator,
       current_setting('server_version_num')::int >= 180000 AS postgresql_18,
       EXISTS (
           SELECT 1 FROM pg_roles WHERE rolname = 'student_xx'
       ) AS student_login_exists
FROM pg_roles
WHERE rolname = current_user;


-- =============================================================================
-- Step 1 — Look before creating
-- Expect no rows on a first run.
-- Expect five rows with role_comment "Security gates lab xx" on a rerun.
-- Stop when a comment is different. Do not retag that role.
-- =============================================================================

SELECT rolname, shobj_description(oid, 'pg_authid') AS role_comment
FROM pg_roles
WHERE rolname IN (
    'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
    'gate_auditor_xx', 'gate_dba_xx'
)
ORDER BY rolname;


-- =============================================================================
-- Step 2 — Create the five roles
-- Skip a statement when its role already exists.
-- None of these roles is superuser. postgres is the only superuser here.
-- =============================================================================

CREATE ROLE gate_owner_xx
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE gate_staff_xx
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE gate_app_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE gate_auditor_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE gate_dba_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

COMMENT ON ROLE gate_owner_xx IS 'Security gates lab xx';
COMMENT ON ROLE gate_staff_xx IS 'Security gates lab xx';
COMMENT ON ROLE gate_app_xx IS 'Security gates lab xx';
COMMENT ON ROLE gate_auditor_xx IS 'Security gates lab xx';
COMMENT ON ROLE gate_dba_xx IS 'Security gates lab xx';


-- =============================================================================
-- Step 3 — Let student_xx act as each role
-- INHERIT FALSE: a query run as student_xx does not receive the role's grants.
-- SET TRUE: SET ROLE works.
-- ADMIN TRUE on gate_staff_xx only: the student can grant that group to the app.
-- =============================================================================

GRANT gate_owner_xx TO student_xx
    WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT gate_staff_xx TO student_xx
    WITH INHERIT FALSE, SET TRUE, ADMIN TRUE;
GRANT gate_app_xx TO student_xx
    WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT gate_auditor_xx TO student_xx
    WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT gate_dba_xx TO student_xx
    WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;

-- The student lab grants CONNECT itself. This makes that GRANT possible
-- even when student_xx is not the database owner.
GRANT CREATE ON DATABASE claimsure_xx TO student_xx;
GRANT CONNECT ON DATABASE claimsure_xx TO student_xx WITH GRANT OPTION;


-- =============================================================================
-- Step 4 — Confirm, then leave postgres
-- Expect five rows.
-- inherit_option is false on every row.
-- set_option is true on every row.
-- admin_option is true only for gate_staff_xx.
-- Expect student_inherits_owner = false.
-- Expect student_can_create_schema and student_can_grant_connect = true.
-- =============================================================================

SELECT r.rolname AS may_set_role,
       am.inherit_option,
       am.set_option,
       am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname = 'student_xx'
  AND r.rolname IN (
      'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
      'gate_auditor_xx', 'gate_dba_xx'
  )
ORDER BY r.rolname;

SELECT pg_has_role('student_xx', 'gate_owner_xx', 'SET') AS student_can_set_owner,
       pg_has_role('student_xx', 'gate_owner_xx', 'USAGE') AS student_inherits_owner,
       has_database_privilege('student_xx', 'claimsure_xx', 'CREATE') AS student_can_create_schema,
       has_database_privilege(
           'student_xx', 'claimsure_xx', 'CONNECT WITH GRANT OPTION'
       ) AS student_can_grant_connect;

-- Reconnect as student_xx before the next file.
-- The prompt must change from claimsure_xx=# to claimsure_xx=>
-- Then run 04-security-gates-student.sql from Step 0.

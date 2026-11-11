\set ON_ERROR_STOP on
-- Replace every xx with your assigned two-digit number before running.
DO $$
BEGIN
  IF current_database() <> 'claimsure_xx' THEN
    RAISE EXCEPTION 'Wrong connection or unresolved xx placeholder; verify your assigned database/login first';
  END IF;
END $$;

-- Reset the security-gates lab for student xx. Plain SQL.
-- Run the steps in order. Do not execute the whole file at once.
-- Login for every step: postgres, database claimsure_xx.
-- The prompt must be claimsure_xx=#
-- student_xx cannot drop these roles. A prompt of claimsure_xx=> is the wrong login.
-- This also revokes the activation grants from student_xx.
-- It does not remove role student_xx or that role's own CONNECT privilege.
--
-- This removes only:
--   schema lab_gate_xx
--   roles  gate_owner_xx, gate_staff_xx, gate_app_xx,
--          gate_auditor_xx, gate_dba_xx
-- It does not remove database claimsure_xx, role student_xx,
-- the Module 4 roles, schema insurance, or schema public.
--
-- Close any session logged in as gate_app_xx, gate_auditor_xx, or gate_dba_xx
-- before Step 4.
-- DROP OWNED uses RESTRICT. Do not replace RESTRICT with CASCADE.

-- =============================================================================
-- Step 1 — Session
-- Continue only when correct_database and administrator are true.
-- =============================================================================

-- rolsuper is a column of pg_roles, not a session function.
SELECT current_database() AS database_name,
       session_user AS login_user,
       current_user AS effective_user,
       current_database() = 'claimsure_xx' AS correct_database,
       current_user = session_user AND rolsuper AS administrator
FROM pg_roles
WHERE rolname = current_user;


-- =============================================================================
-- Step 2 — Look at what will be removed
-- Expect the five gate_ roles, or fewer when a previous reset already removed some.
-- Expect schema lab_gate_xx owned by gate_owner_xx, or no row when it is already gone.
-- The role comment must be "Security gates lab xx" for every role that is present.
-- Stop when a listed role has a different comment or no comment.
-- =============================================================================

SELECT rolname, shobj_description(oid, 'pg_authid') AS role_comment
FROM pg_roles
WHERE rolname IN (
    'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
    'gate_auditor_xx', 'gate_dba_xx'
)
ORDER BY rolname;

SELECT nspname, pg_get_userbyid(nspowner) AS owner
FROM pg_namespace
WHERE nspname = 'lab_gate_xx';


-- =============================================================================
-- Step 3 — Safety checks
-- Continue to Step 4 only when every column is true.
-- roles_belong_to_this_lab is true when each existing role has this lab's comment.
-- schema_owner_ok is true when the schema is absent or owned by gate_owner_xx.
-- relations_in_scope ignores toast tables. A lab table outside lab_gate_xx
-- makes it false.
-- =============================================================================

SELECT
    current_database() = 'claimsure_xx' AS correct_database,
    current_user = session_user AND rolsuper AS administrator,
    NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname IN (
            'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
            'gate_auditor_xx', 'gate_dba_xx'
        )
          AND shobj_description(oid, 'pg_authid') IS DISTINCT FROM 'Security gates lab xx'
    ) AS roles_belong_to_this_lab,
    NOT EXISTS (
        SELECT 1
        FROM pg_namespace
        WHERE nspname = 'lab_gate_xx'
          AND pg_get_userbyid(nspowner) IS DISTINCT FROM 'gate_owner_xx'
    ) AS schema_owner_ok,
    NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_roles r ON r.oid = c.relowner
        WHERE r.rolname IN (
            'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
            'gate_auditor_xx', 'gate_dba_xx'
        )
          AND n.nspname <> 'lab_gate_xx'
          AND n.nspname <> 'pg_toast'
          AND n.nspname <> 'pg_catalog'
          AND n.nspname NOT LIKE 'pg_toast_temp%'
    ) AS relations_in_scope,
    NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        JOIN pg_roles r ON r.oid = p.proowner
        WHERE r.rolname IN (
            'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
            'gate_auditor_xx', 'gate_dba_xx'
        )
          AND n.nspname <> 'lab_gate_xx'
          AND n.nspname <> 'pg_catalog'
    ) AS routines_in_scope
FROM pg_roles
WHERE rolname = current_user;


-- =============================================================================
-- Step 4 — Remove membership, privileges, the schema, and the roles
-- Run one statement at a time.
-- Skip a statement when its role or membership is already gone.
-- Revoke student_xx first, then the app's membership in the staff group.
-- Non-owners go first, so their grants are cleared before the owner is dropped.
-- =============================================================================

REVOKE gate_owner_xx FROM student_xx;
REVOKE gate_staff_xx FROM student_xx;
REVOKE gate_app_xx FROM student_xx;
REVOKE gate_auditor_xx FROM student_xx;
REVOKE gate_dba_xx FROM student_xx;

REVOKE gate_staff_xx FROM gate_app_xx;

DROP OWNED BY gate_app_xx RESTRICT;
DROP OWNED BY gate_auditor_xx RESTRICT;
DROP OWNED BY gate_dba_xx RESTRICT;
DROP OWNED BY gate_staff_xx RESTRICT;
DROP OWNED BY gate_owner_xx RESTRICT;

DROP ROLE gate_app_xx;
DROP ROLE gate_auditor_xx;
DROP ROLE gate_dba_xx;
DROP ROLE gate_staff_xx;
DROP ROLE gate_owner_xx;


-- =============================================================================
-- Step 5 — Confirm
-- Expect remaining_gate_roles = 0.
-- Expect student_still_member = 0.
-- Expect remaining_schema to be null.
-- Database claimsure_xx is still there.
-- =============================================================================

SELECT count(*) AS remaining_gate_roles
FROM pg_roles
WHERE rolname IN (
    'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
    'gate_auditor_xx', 'gate_dba_xx'
);

SELECT count(*) AS student_still_member
FROM pg_auth_members am
JOIN pg_roles granted ON granted.oid = am.roleid
JOIN pg_roles member ON member.oid = am.member
WHERE member.rolname = 'student_xx'
  AND granted.rolname IN (
      'gate_owner_xx', 'gate_staff_xx', 'gate_app_xx',
      'gate_auditor_xx', 'gate_dba_xx'
  );

SELECT to_regnamespace('lab_gate_xx') AS remaining_schema;

SELECT current_database() AS database_still_present;

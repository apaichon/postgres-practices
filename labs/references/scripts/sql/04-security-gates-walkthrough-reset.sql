\set ON_ERROR_STOP on
\pset pager off
\echo '=== Reset the security-gates walkthrough for ONE student ==='

-- Removes lab_gate_xx and the five gate_* roles for this student number.
-- Does not remove claimsure_xx, student_xx, the Module 4 roles, insurance,
-- or public.
--
-- From the postgres-admin-labs directory, as the lab superuser:
--   ROLLBACK;
--   \connect claimsure_xx postgres
--   \set student_no xx
--   \i scripts/sql/04-security-gates-walkthrough-reset.sql
--
-- Close any session logged in as gate_app_xx, gate_auditor_xx, or gate_dba_xx
-- first. DROP OWNED uses RESTRICT. An object these roles own outside
-- lab_gate_xx stops the reset. Do not replace RESTRICT with CASCADE.

\if :{?student_no}
\else
DO $$ BEGIN RAISE EXCEPTION 'Set student_no first, for example: \set student_no xx'; END $$;
\endif
SELECT :'student_no' ~ '^(0[1-9]|1[0-9]|20)$'
       AND current_database() = 'claimsure_' || :'student_no' AS correct_target,
       current_user = session_user AND rolsuper AS administrator
FROM pg_roles WHERE rolname = current_user \gset
\if :correct_target
\else
DO $$ BEGIN RAISE EXCEPTION 'Use student_no xx..20 and connect to matching claimsure_xx.'; END $$;
\endif
\if :administrator
\else
DO $$ BEGIN RAISE EXCEPTION 'ROLLBACK and reconnect as the lab superuser before resetting.'; END $$;
\endif
SELECT current_database() AS lab_database,
       'lab_gate_' || :'student_no' AS lab_schema,
       'gate_owner_' || :'student_no' AS owner_role,
       'gate_staff_' || :'student_no' AS staff_role,
       'gate_app_' || :'student_no' AS app_role,
       'gate_auditor_' || :'student_no' AS auditor_role,
       'gate_dba_' || :'student_no' AS dba_role,
       'Security gates lab ' || :'student_no' AS role_marker
\gset
SET lock_timeout = '5s';

SELECT NOT EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                                :'auditor_role', :'dba_role'])
      AND shobj_description(oid, 'pg_authid') IS DISTINCT FROM :'role_marker'
) AS safe_role_names \gset
\if :safe_role_names
\else
DO $$ BEGIN RAISE EXCEPTION 'A gate_* role for this student is not marked as this walkthrough. Reset stopped.'; END $$;
\endif
SELECT NOT EXISTS (
    SELECT 1 FROM pg_namespace
    WHERE nspname = :'lab_schema'
      AND pg_get_userbyid(nspowner) IS DISTINCT FROM :'owner_role'
) AS schema_owner_ok \gset
\if :schema_owner_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'lab_gate_xx has an unexpected owner. Reset stopped.'; END $$;
\endif
-- Toast tables live in pg_toast and are expected. Anything else outside
-- the lab schema means this role was used for other work.
SELECT NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_roles r ON r.oid = c.relowner
    WHERE r.rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                                  :'auditor_role', :'dba_role'])
      AND n.nspname <> :'lab_schema'
      AND n.nspname <> 'pg_toast'
      AND n.nspname !~ '^pg_toast_temp'
      AND n.nspname <> 'pg_catalog'
) AS relations_in_scope \gset
\if :relations_in_scope
\else
DO $$ BEGIN RAISE EXCEPTION 'A walkthrough role owns a relation outside lab_gate_xx. Reset stopped.'; END $$;
\endif
SELECT NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE r.rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                                  :'auditor_role', :'dba_role'])
      AND n.nspname <> :'lab_schema'
      AND n.nspname <> 'pg_catalog'
) AS routines_in_scope \gset
\if :routines_in_scope
\else
DO $$ BEGIN RAISE EXCEPTION 'A walkthrough role owns a routine outside lab_gate_xx. Reset stopped.'; END $$;
\endif

\echo 'Roles and schema that will be removed:'
SELECT rolname FROM pg_roles
WHERE rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                            :'auditor_role', :'dba_role'])
ORDER BY rolname;
SELECT nspname, pg_get_userbyid(nspowner) AS owner
FROM pg_namespace WHERE nspname = :'lab_schema';

BEGIN;
SELECT format('REVOKE %I FROM %I', :'staff_role', :'app_role')
WHERE EXISTS (
    SELECT 1
    FROM pg_auth_members am
    JOIN pg_roles g ON g.oid = am.roleid AND g.rolname = :'staff_role'
    JOIN pg_roles m ON m.oid = am.member AND m.rolname = :'app_role'
) \gexec
-- Privileges and owned objects in this database, including the lab schema.
-- Non-owners first, so their grants are cleared before the owner is dropped.
SELECT format('DROP OWNED BY %I RESTRICT', rolname)
FROM pg_roles
WHERE rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                            :'auditor_role', :'dba_role'])
ORDER BY (rolname = :'owner_role'), rolname
\gexec
SELECT format('DROP ROLE %s', string_agg(format('%I', rolname), ', ' ORDER BY rolname))
FROM pg_roles
WHERE rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                            :'auditor_role', :'dba_role'])
HAVING count(*) > 0
\gexec
COMMIT;

SELECT count(*) AS remaining_gate_roles
FROM pg_roles
WHERE rolname = ANY (ARRAY[:'owner_role', :'staff_role', :'app_role',
                            :'auditor_role', :'dba_role']);
SELECT to_regnamespace(:'lab_schema') AS remaining_schema;
\echo 'RESET COMPLETE for student' :student_no
\echo 'Expected: remaining_gate_roles = 0 and remaining_schema is null.'
\echo 'The database' :lab_database 'is still there.'

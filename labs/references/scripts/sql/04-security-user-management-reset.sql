\set ON_ERROR_STOP on
\pset pager off
\echo '=== Reset Module 4 for ONE student: deletes that lab schema, data and 11 roles ==='
-- Run as the lab superuser, connected to claimsure_xx, with student_no=xx.
-- Example in psql (repository root):
--   ROLLBACK;
--   \connect claimsure_xx postgres
--   \set student_no xx
--   \i scripts/sql/04-security-user-management-reset.sql
-- Close application test sessions first. No live server is reset automatically.
-- Scope: only the exact Module 4 role names for this student; not student_xx,
-- postgres, predefined roles, insurance, public, or other students.
-- DROP OWNED uses RESTRICT. Cross-database dependencies or unexpected
-- ownership stop the reset; do not replace RESTRICT with CASCADE blindly.

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
DO $$ BEGIN RAISE EXCEPTION 'ROLLBACK and reconnect as the lab superuser (normally postgres) before resetting.'; END $$;
\endif
SELECT 'lab_m4_' || :'student_no' AS lab_schema,
       'claimsure_owner_' || :'student_no' AS owner_role
\gset

BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TEMP TABLE m4_reset_roles (rolname name PRIMARY KEY) ON COMMIT DROP;
INSERT INTO m4_reset_roles
SELECT prefix || :'student_no' FROM unnest(ARRAY[
    'claimsure_owner_', 'claimsure_read_', 'claimsure_write_',
    'claimsure_approve_', 'claimsure_audit_', 'claim_app_',
    'adjuster_bkk_', 'manager_th_', 'internal_auditor_',
    'claim_monitor_', 'claim_dba_'
]) AS prefix;

-- Display the exact existing roles and lab schema before removing them.
SELECT r.rolname FROM pg_roles r JOIN m4_reset_roles t USING (rolname) ORDER BY r.rolname;
SELECT nspname, pg_get_userbyid(nspowner) AS owner
FROM pg_namespace WHERE nspname = :'lab_schema';

-- A same-named schema owned outside this lab needs instructor review.
SELECT NOT EXISTS (
    SELECT 1 FROM pg_namespace n
    WHERE n.nspname = :'lab_schema'
      AND pg_get_userbyid(n.nspowner) <> :'owner_role'
) AS correct_schema_owner \gset
\if :correct_schema_owner
\else
DO $$ BEGIN RAISE EXCEPTION 'The lab schema has an unexpected owner. Reset stopped without changes; ask the instructor to inspect it.'; END $$;
\endif

-- Refuse to remove objects these roles own outside the designated schema,
-- including owned shared objects such as a database or tablespace.
SELECT NOT EXISTS (
    SELECT 1
    FROM pg_shdepend d
    JOIN pg_roles r ON r.oid = d.refobjid
    JOIN m4_reset_roles t ON t.rolname = r.rolname
    WHERE d.refclassid = 'pg_authid'::regclass AND d.deptype = 'o'
      AND NOT CASE
        WHEN d.dbid = 0 THEN false
        -- Objects in another database cannot be resolved by local catalogs.
        -- DROP ROLE will reject these dependencies and roll back this reset.
        WHEN d.dbid <> (SELECT oid FROM pg_database WHERE datname = current_database())
          THEN true
        WHEN d.classid = 'pg_namespace'::regclass
          THEN d.objid = coalesce((SELECT oid FROM pg_namespace WHERE nspname = :'lab_schema'), 0)
        WHEN d.classid = 'pg_default_acl'::regclass
          THEN EXISTS (SELECT 1 FROM pg_default_acl a
                       JOIN pg_namespace n ON n.oid = a.defaclnamespace
                       WHERE a.oid = d.objid AND n.nspname = :'lab_schema')
        ELSE coalesce(
          (pg_identify_object(d.classid, d.objid, d.objsubid)).schema = :'lab_schema',
          false)
      END
) AS ownership_in_scope \gset
\if :ownership_in_scope
\else
DO $$ BEGIN RAISE EXCEPTION 'A target role owns an object outside its Module 4 schema. Reset stopped without changes; inspect the role dependencies.'; END $$;
\endif

-- Remove grants from recipients first, then remove the owner's objects.
-- Separate statements refresh default-ACL dependencies between roles.
SELECT format('DROP OWNED BY %I RESTRICT', r.rolname)
FROM pg_roles r JOIN m4_reset_roles t USING (rolname)
ORDER BY (r.rolname = :'owner_role'), r.rolname
\gexec
-- DROP OWNED also removes grants/default ACLs in this database and grants
-- on shared objects. DROP ROLE automatically removes their memberships.
SELECT format('DROP ROLE %s',
              string_agg(format('%I', r.rolname), ', ' ORDER BY r.rolname))
FROM pg_roles r JOIN m4_reset_roles t USING (rolname)
HAVING count(*) > 0
\gexec
COMMIT;

SELECT count(*) AS remaining_module4_roles
FROM pg_roles
WHERE rolname = ANY (ARRAY[
    'claimsure_owner_' || :'student_no', 'claimsure_read_' || :'student_no',
    'claimsure_write_' || :'student_no', 'claimsure_approve_' || :'student_no',
    'claimsure_audit_' || :'student_no', 'claim_app_' || :'student_no',
    'adjuster_bkk_' || :'student_no', 'manager_th_' || :'student_no',
    'internal_auditor_' || :'student_no', 'claim_monitor_' || :'student_no',
    'claim_dba_' || :'student_no'
]);
-- EXPECT: 0. The student's module schema is gone; their database remains.
\echo 'RESET COMPLETE for student' :student_no '| Start again at Lab 4A.'

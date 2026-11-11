\set ON_ERROR_STOP on
\echo 'Module 4: own database, per-student temporary roles, all changes rolled back'
SELECT 'course_m4_reader_'||right(current_user,2) AS reader,
       'course_m4_actor_'||right(current_user,2) AS actor,current_user AS owner,current_database() AS db \gset
SELECT NOT EXISTS(SELECT FROM pg_roles WHERE rolname IN (:'reader',:'actor')) AS names_available \gset
\if :names_available
\else
 \echo 'Reserved course role names already exist; preserving them.'
 \quit 1
\endif
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE ROLE :"reader" NOLOGIN;
CREATE ROLE :"actor" NOLOGIN;
GRANT :"reader" TO :"actor";
GRANT :"actor" TO :"owner" WITH SET TRUE, INHERIT FALSE;
GRANT CONNECT ON DATABASE :"db" TO :"actor";
GRANT USAGE ON SCHEMA lab_m4_shell TO :"reader";
GRANT SELECT,INSERT ON lab_m4_shell.claim_secure TO :"reader";
REVOKE CREATE ON SCHEMA lab_m4_shell FROM PUBLIC;
ALTER TABLE lab_m4_shell.claim_secure ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_m4_shell.claim_secure FORCE ROW LEVEL SECURITY;
CREATE POLICY course_tenant ON lab_m4_shell.claim_secure
USING(tenant_id=nullif(current_setting('app.course_tenant',true),'')::int)
WITH CHECK(tenant_id=nullif(current_setting('app.course_tenant',true),'')::int);
CREATE FUNCTION lab_m4_shell.tenant_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER
SET search_path=pg_catalog,lab_m4_shell AS $$SELECT count(*) FROM lab_m4_shell.claim_secure$$;
REVOKE ALL ON FUNCTION lab_m4_shell.tenant_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION lab_m4_shell.tenant_count() TO :"reader";
SET LOCAL ROLE :"actor";
SELECT set_config('app.course_tenant','101',true);
SELECT current_user,session_user,count(*) AS tenant_101_rows FROM lab_m4_shell.claim_secure;
DO $$
BEGIN
 IF (SELECT count(*) FROM lab_m4_shell.claim_secure)<>2 OR lab_m4_shell.tenant_count()<>2 THEN
  RAISE EXCEPTION 'RLS/definer count did not equal 2';
 END IF;
 BEGIN
  EXECUTE 'CREATE TABLE lab_m4_shell.denied_object(id int)';
  RAISE EXCEPTION 'Unexpected schema CREATE permission';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS schema CREATE denied: 42501'; END;
 BEGIN
  INSERT INTO lab_m4_shell.claim_secure VALUES(999,202,'denied tenant',1);
  RAISE EXCEPTION 'Unexpected cross-tenant INSERT';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS RLS WITH CHECK denied: 42501'; END;
END $$;
RESET ROLE;
CREATE FUNCTION lab_m4_shell.audit_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,lab_m4_shell AS $$BEGIN
 INSERT INTO lab_m4_shell.claim_audit(actor,operation,claim_id) VALUES(session_user,TG_OP,NEW.id);
 RETURN NEW; END$$;
CREATE TRIGGER course_audit AFTER UPDATE ON lab_m4_shell.claim_secure FOR EACH ROW EXECUTE FUNCTION lab_m4_shell.audit_change();
SELECT count(*) AS audit_before FROM lab_m4_shell.claim_audit \gset
UPDATE lab_m4_shell.claim_secure SET note='audit test' WHERE id=1;
SELECT count(*)=(:audit_before+1) AS audit_ok FROM lab_m4_shell.claim_audit \gset
\if :audit_ok
 \echo 'PASS audit trigger recorded the test update'
\else
 \quit 1
\endif
ROLLBACK;
SELECT count(*)=0 AS roles_removed FROM pg_roles WHERE rolname IN (:'reader',:'actor') \gset
\if :roles_removed
 \echo 'PASS temporary roles, grants, policy, functions, trigger and data changes rolled back'
\else
 \quit 1
\endif

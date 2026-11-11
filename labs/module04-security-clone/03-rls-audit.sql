\ir context.sql
-- Run after the staged GRANT exercises in the Markdown guide.
BEGIN;
SET LOCAL ROLE :"owner_role";

CREATE TABLE :"lab_schema".login_customer (
  login_name name PRIMARY KEY,
  customer_id bigint NOT NULL REFERENCES :"lab_schema".customer(customer_id)
);
INSERT INTO :"lab_schema".login_customer
SELECT login_name, c.customer_id
FROM (VALUES (:'read_a', 'CUS-001'), (:'read_b', 'CUS-002'),
             (:'create_a', 'CUS-001'), (:'approve_a', 'CUS-001')) AS m(login_name, customer_code)
JOIN :"lab_schema".customer c USING (customer_code);
SELECT count(*) = 4 AS four_mappings FROM :"lab_schema".login_customer
\gset
\if :four_mappings
\else
  \echo 'Missing CUS-001/CUS-002 in the cloned data; setup cannot continue.'
  DO $$ BEGIN RAISE EXCEPTION 'Lab prerequisite or confirmation failed; see the message above.'; END $$;
\endif
REVOKE ALL ON :"lab_schema".login_customer FROM PUBLIC;

CREATE FUNCTION :"lab_schema".allowed_policy_ids() RETURNS SETOF bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, :"lab_schema", pg_temp
AS $function$
  SELECT p.policy_id FROM policy p
  JOIN login_customer m USING (customer_id)
  WHERE m.login_name = session_user
$function$;
REVOKE ALL ON FUNCTION :"lab_schema".allowed_policy_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION :"lab_schema".allowed_policy_ids() TO :"reader_role";

ALTER TABLE :"lab_schema".claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE :"lab_schema".claim FORCE ROW LEVEL SECURITY;
CREATE POLICY m4_owner ON :"lab_schema".claim TO :"owner_role" USING (true) WITH CHECK (true);
CREATE POLICY m4_read ON :"lab_schema".claim FOR SELECT TO :"reader_role"
  USING (policy_id IN (SELECT :"lab_schema".allowed_policy_ids()));
CREATE POLICY m4_insert ON :"lab_schema".claim FOR INSERT TO :"writer_role"
  WITH CHECK (status = 'NEW' AND policy_id IN (SELECT :"lab_schema".allowed_policy_ids()));
CREATE POLICY m4_approve ON :"lab_schema".claim FOR UPDATE TO :"approver_role"
  USING (policy_id IN (SELECT :"lab_schema".allowed_policy_ids()))
  WITH CHECK (policy_id IN (SELECT :"lab_schema".allowed_policy_ids()));

CREATE TABLE :"lab_schema".claim_audit (
  audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_id bigint NOT NULL, claim_no text NOT NULL,
  old_status text NOT NULL, new_status text NOT NULL,
  login_name name NOT NULL, changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON :"lab_schema".claim_audit FROM PUBLIC;
CREATE FUNCTION :"lab_schema".audit_claim_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, :"lab_schema", pg_temp
AS $function$
BEGIN
  INSERT INTO claim_audit(claim_id, claim_no, old_status, new_status, login_name)
  VALUES (NEW.claim_id, NEW.claim_no, OLD.status, NEW.status, session_user);
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION :"lab_schema".audit_claim_status() FROM PUBLIC;
CREATE TRIGGER m4_status_audit AFTER UPDATE OF status ON :"lab_schema".claim
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION :"lab_schema".audit_claim_status();
GRANT USAGE ON SCHEMA :"lab_schema" TO :"auditor_role";
GRANT SELECT ON :"lab_schema".claim_audit TO :"auditor_role";
COMMIT;
\echo 'Persistent RLS + audit installed. Reconnect as the actual lab login to test session_user mapping.'

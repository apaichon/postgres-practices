\ir context.sql

SELECT to_regnamespace(:'lab_schema') IS NULL
       AND to_regclass('claimsure.customer') IS NOT NULL
       AND to_regclass('claimsure.policy') IS NOT NULL
       AND to_regclass('claimsure.claim') IS NOT NULL
       AND EXISTS (SELECT FROM pg_roles WHERE rolname = :'owner_role') AS ready_to_clone
\gset
\if :ready_to_clone
\else
  \echo 'Need source customer/policy/claim, prepared roles, and an unused lab schema.'
  DO $$ BEGIN RAISE EXCEPTION 'Lab prerequisite or confirmation failed; see the message above.'; END $$;
\endif

-- This is a scoped clone of the three course business tables, not a generic
-- whole-schema clone. Reject serial-style defaults that LIKE could share.
DO $guard$
BEGIN
  IF EXISTS (
    SELECT FROM pg_attrdef d JOIN pg_attribute a
      ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE d.adrelid IN ('claimsure.customer'::regclass, 'claimsure.policy'::regclass, 'claimsure.claim'::regclass)
      AND pg_get_expr(d.adbin, d.adrelid) ~ 'nextval\('
  ) THEN
    RAISE EXCEPTION 'Unsupported sequence-backed default; do not share source sequences through LIKE.';
  END IF;
  IF EXISTS (
    SELECT FROM (VALUES ('claimsure.customer'::regclass, 'customer_id'),
                       ('claimsure.policy'::regclass, 'policy_id'),
                       ('claimsure.claim'::regclass, 'claim_id')) AS ids(relid, col)
    WHERE NOT EXISTS (SELECT FROM pg_attribute a
                      WHERE a.attrelid = ids.relid AND a.attname = ids.col AND a.attidentity <> '')
  ) THEN
    RAISE EXCEPTION 'Expected course identity primary keys on all three source tables.';
  END IF;
END
$guard$;

BEGIN ISOLATION LEVEL REPEATABLE READ;
CREATE SCHEMA :"lab_schema" AUTHORIZATION :"owner_role";
REVOKE ALL ON SCHEMA :"lab_schema" FROM PUBLIC;
COMMENT ON SCHEMA :"lab_schema" IS 'module04-security-clone-v1';
SET LOCAL search_path = pg_catalog;

CREATE TABLE :"lab_schema".customer (LIKE claimsure.customer INCLUDING ALL);
CREATE TABLE :"lab_schema".policy (LIKE claimsure.policy INCLUDING ALL);
CREATE TABLE :"lab_schema".claim (LIKE claimsure.claim INCLUDING ALL);

-- Include ordinary and identity columns; recompute any generated columns.
SELECT format('INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM claimsure.%I',
              :'lab_schema', c.relname,
              string_agg(format('%I', a.attname), ', ' ORDER BY a.attnum),
              string_agg(format('%I', a.attname), ', ' ORDER BY a.attnum), c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid
WHERE n.nspname = 'claimsure' AND c.relname IN ('customer', 'policy', 'claim')
  AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = ''
GROUP BY c.relname
ORDER BY CASE c.relname WHEN 'customer' THEN 1 WHEN 'policy' THEN 2 ELSE 3 END
\gexec

-- LIKE does not copy foreign keys. These references must stay inside the clone.
ALTER TABLE :"lab_schema".policy ADD CONSTRAINT m4_policy_customer_fk
  FOREIGN KEY (customer_id) REFERENCES :"lab_schema".customer(customer_id);
ALTER TABLE :"lab_schema".claim ADD CONSTRAINT m4_claim_policy_fk
  FOREIGN KEY (policy_id) REFERENCES :"lab_schema".policy(policy_id);

SELECT format('SELECT setval(pg_get_serial_sequence(%L, %L), '
              'COALESCE((SELECT max(%I) FROM %I.%I), 1), '
              'EXISTS (SELECT FROM %I.%I))',
              format('%I.%I', :'lab_schema', tbl), id_col, id_col,
              :'lab_schema', tbl, :'lab_schema', tbl)
FROM (VALUES ('customer', 'customer_id'), ('policy', 'policy_id'), ('claim', 'claim_id')) AS ids(tbl, id_col)
\gexec

ALTER TABLE :"lab_schema".customer OWNER TO :"owner_role";
ALTER TABLE :"lab_schema".policy OWNER TO :"owner_role";
ALTER TABLE :"lab_schema".claim OWNER TO :"owner_role";
REVOKE ALL ON ALL TABLES IN SCHEMA :"lab_schema" FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA :"lab_schema" FROM PUBLIC;

-- Record every source row, source ACL/RLS and sequence state before exercises.
CREATE TABLE :"lab_schema".source_manifest (
  table_name name PRIMARY KEY, source_rows bigint NOT NULL, source_hash text NOT NULL,
  source_acl text, source_rls boolean NOT NULL, source_force_rls boolean NOT NULL,
  source_sequence text NOT NULL, source_last_value bigint NOT NULL, source_is_called boolean NOT NULL
);
SELECT format('INSERT INTO %I.source_manifest '
  'SELECT %L, count(*), md5(COALESCE(string_agg(md5(to_jsonb(s)::text), '''' ORDER BY %I), '''')), '
  '(SELECT relacl::text FROM pg_class WHERE oid = %L::regclass), '
  '(SELECT relrowsecurity FROM pg_class WHERE oid = %L::regclass), '
  '(SELECT relforcerowsecurity FROM pg_class WHERE oid = %L::regclass), '
  '%L, (SELECT last_value FROM %s), (SELECT is_called FROM %s) FROM claimsure.%I s',
  :'lab_schema', tbl, id_col, 'claimsure.' || tbl, 'claimsure.' || tbl, 'claimsure.' || tbl,
  pg_get_serial_sequence('claimsure.' || tbl, id_col),
  pg_get_serial_sequence('claimsure.' || tbl, id_col),
  pg_get_serial_sequence('claimsure.' || tbl, id_col), tbl)
FROM (VALUES ('customer', 'customer_id'), ('policy', 'policy_id'), ('claim', 'claim_id')) AS ids(tbl, id_col)
\gexec
ALTER TABLE :"lab_schema".source_manifest OWNER TO :"owner_role";

SET LOCAL ROLE :"owner_role";
CREATE VIEW :"lab_schema".claim_detail_v WITH (security_invoker = true) AS
SELECT cl.claim_id, cl.claim_no, cl.status, cl.incident_at, cl.estimated_amount,
       cl.approved_amount, p.policy_no, p.product_code, c.customer_code, c.full_name
FROM :"lab_schema".claim cl
JOIN :"lab_schema".policy p USING (policy_id)
JOIN :"lab_schema".customer c USING (customer_id);
COMMIT;
\echo 'Cloned customer/policy/claim, rebuilt local FKs, independent identity sequences and local view. No app grants yet.'

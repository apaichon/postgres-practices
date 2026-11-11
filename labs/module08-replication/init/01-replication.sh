#!/usr/bin/env bash
set -Eeuo pipefail
# Runs once on primary. Physical standbys receive this state via base backup.
psql -X -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=repl_password="$M8_REPLICATION_PASSWORD" --set=app_password="$M8_APP_PASSWORD" <<'SQL'
CREATE ROLE replicator WITH LOGIN REPLICATION NOSUPERUSER NOCREATEDB NOCREATEROLE
  PASSWORD :'repl_password';
CREATE ROLE claim_app WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS
  PASSWORD :'app_password';
\i /lab/sql/schema.sql
CREATE SCHEMA lab_m8;
CREATE TABLE insurance.audit_event (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id bigint NOT NULL,
  actor text NOT NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO insurance.claim (tenant_id, claim_no, status, amount) VALUES
  (1, 'CLM-M8-001', 'NEW', 1000), (1, 'CLM-M8-002', 'REVIEW', 2000),
  (2, 'CLM-M8-003', 'NEW', 3000);
INSERT INTO insurance.claim_payment (tenant_id, claim_id, amount)
SELECT tenant_id, claim_id, amount / 2 FROM insurance.claim;
GRANT CONNECT ON DATABASE claimsure TO replicator, claim_app;
GRANT USAGE ON SCHEMA insurance TO replicator, claim_app;
GRANT SELECT ON insurance.claim, insurance.claim_payment TO replicator;
GRANT SELECT ON insurance.claim TO claim_app;
ALTER TABLE insurance.claim ENABLE ROW LEVEL SECURITY;
CREATE POLICY claim_tenant ON insurance.claim FOR SELECT TO claim_app
  USING (tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint);
CREATE POLICY claim_replication ON insurance.claim FOR SELECT TO replicator USING (true);
SQL

\set ON_ERROR_STOP on
\pset pager off
-- Run only in the dedicated database created by the instructor.
DO $$
BEGIN
  IF current_database() !~ '^architecture_m5_(0[1-9]|1[0-9]|20)$' THEN
    RAISE EXCEPTION 'Use a dedicated architecture_m5_01..20 database, not the continuous course database';
  END IF;
  IF pg_is_in_recovery() OR NOT EXISTS
    (SELECT FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    RAISE EXCEPTION 'Use the instructor superuser on a writable lab server';
  END IF;
END $$;

BEGIN;
CREATE SCHEMA IF NOT EXISTS insurance;
CREATE TABLE IF NOT EXISTS insurance.policy (
  policy_id bigint PRIMARY KEY,
  policy_no text NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS insurance.claim (
  claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id bigint NOT NULL,
  claim_no text NOT NULL UNIQUE,
  policy_id bigint NOT NULL REFERENCES insurance.policy(policy_id),
  status text NOT NULL CHECK (status IN ('NEW', 'REVIEW', 'APPROVED', 'REJECTED')),
  incident_at timestamptz NOT NULL,
  estimated_amount numeric(12,2) NOT NULL,
  approved_amount numeric(12,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT '2026-01-05 09:00:00+07'
);
CREATE TABLE IF NOT EXISTS insurance.audit_event (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id bigint NOT NULL,
  actor text NOT NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO insurance.policy VALUES (1, 'POL-M5-001'), (2, 'POL-M5-002'), (3, 'POL-M5-003')
ON CONFLICT DO NOTHING;
INSERT INTO insurance.claim
  (tenant_id, claim_no, policy_id, status, incident_at, estimated_amount, approved_amount)
VALUES
  (1, 'CLM-L1-001', 1, 'NEW',      '2026-01-01 10:00:00+07', 15000, 0),
  (1, 'CLM-L1-002', 1, 'REVIEW',   '2026-01-02 10:00:00+07', 20000, 0),
  (1, 'CLM-L1-003', 2, 'APPROVED', '2026-01-03 10:00:00+07', 30000, 25000),
  (2, 'CLM-L1-004', 3, 'NEW',      '2026-01-04 10:00:00+07', 25000, 0),
  (1, 'CLM-L1-005', 2, 'NEW',      '2026-01-05 10:00:00+07', 12000, 0),
  (2, 'CLM-L1-006', 3, 'REJECTED', '2026-01-06 10:00:00+07', 18000, 0),
  (1, 'CLM-1001',   1, 'NEW',      '2026-01-01 10:00:00+07', 10000, 0)
ON CONFLICT (claim_no) DO NOTHING;
COMMIT;

SELECT claim_no, status, estimated_amount FROM insurance.claim ORDER BY claim_id;
-- Six CLM-L1 claims plus CLM-1001 referenced by the upstream preflight/audit.
-- Re-running setup keeps existing rows and completed lab changes.

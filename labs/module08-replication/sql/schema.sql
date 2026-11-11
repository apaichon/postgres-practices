-- Logical replication needs matching table definitions before subscription.
CREATE SCHEMA IF NOT EXISTS insurance;
CREATE TABLE IF NOT EXISTS insurance.claim (
  claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id bigint NOT NULL,
  claim_no text NOT NULL UNIQUE,
  status text NOT NULL,
  amount numeric(12,2) NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS insurance.claim_payment (
  payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id bigint NOT NULL,
  claim_id bigint NOT NULL REFERENCES insurance.claim(claim_id),
  amount numeric(12,2) NOT NULL
);
